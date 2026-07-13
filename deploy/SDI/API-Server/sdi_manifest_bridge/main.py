from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from .core.enrichment import enrich_manifest
from .core.client import SDIClient
from .core.bundle import IaCMaleBundle, validate_bundle, convert_bundle, resource_summary
from .k8s.client import k8s_client
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="SDI Manifest Bridge API")
sdi_client = SDIClient()

# 앤시블이 호출하는 주소 (/v1/apply)와 제가 만든 주소 (/deploy) 모두 지원
@app.post("/v1/apply")
@app.post("/deploy")
async def deploy(request: Request):
    try:
        user_input = await request.json()
        logger.info(f"Received deployment request: {user_input}")
        
        # 3개 리소스(Deployment, MaleWorkload, PropagationPolicy) 생성
        resources = enrich_manifest(user_input)
        
        # 순서대로 적용
        results = sdi_client.apply_resources(resources)
        
        return {
            "status": "SUCCESS", # 앤시블이 기대하는 필드명
            "message": "Deployment process completed",
            "results": results,
            "resource": {"name": resources[0]['metadata']['name']} if resources else {}
        }
    except Exception as e:
        logger.error(f"Deployment failed: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

# --- ETRI IaC + MALE Binding 번들 API (Issue #1 합의) ---------------------
# render-bundle: 검증 + 리소스 렌더링 + dry-run만 수행 (클러스터 변경 없음)
# apply-bundle : 검증 후 합의된 순서대로 실제 적용
# 검증은 번들 단위 all-or-nothing: 에러가 하나라도 있으면 전체 거부

def _render(bundle: IaCMaleBundle):
    """공통 경로: 검증 실패 시 HTTPException(400), 성공 시 적용 순서의 리소스 목록 반환."""
    errors = validate_bundle(bundle)
    if errors:
        logger.warning(f"Bundle '{bundle.bundleId}' rejected: {errors}")
        raise HTTPException(status_code=400, detail={
            "status": "REJECTED",
            "bundleId": bundle.bundleId,
            "errors": errors,
        })
    return convert_bundle(bundle)


@app.post("/v1/render-bundle")
async def render_bundle(bundle: IaCMaleBundle):
    logger.info(f"Received render-bundle request: bundleId={bundle.bundleId}")
    resources = _render(bundle)

    dry_run_results = []
    ok = True
    for res in resources:
        kind = res.get("kind")
        name = res.get("metadata", {}).get("name")
        try:
            k8s_client.apply(res, dry_run=True)
            dry_run_results.append({"kind": kind, "name": name, "status": "valid"})
        except Exception as e:
            ok = False
            dry_run_results.append({"kind": kind, "name": name, "status": "invalid",
                                    "error": str(e)})

    body = {
        "status": "RENDERED" if ok else "FAILED",
        "bundleId": bundle.bundleId,
        "missionId": bundle.missionId,
        "resources": resource_summary(resources),
        "dryRun": dry_run_results,
    }
    return body if ok else JSONResponse(status_code=422, content=body)


@app.post("/v1/apply-bundle")
async def apply_bundle(bundle: IaCMaleBundle):
    logger.info(f"Received apply-bundle request: bundleId={bundle.bundleId}")
    resources = _render(bundle)

    applied, skipped = [], []
    failed = None
    for i, res in enumerate(resources):
        kind = res.get("kind")
        name = res.get("metadata", {}).get("name")
        try:
            k8s_client.apply(res)
            applied.append({"kind": kind, "name": name, "status": "applied"})
        except Exception as e:
            # 순서 보장을 위해 첫 실패 지점에서 중단하고 남은 리소스는 건너뜀
            logger.error(f"apply-bundle '{bundle.bundleId}' failed at {kind}/{name}: {e}")
            failed = {"kind": kind, "name": name, "error": str(e)}
            skipped = resource_summary(resources[i + 1:])
            break

    if failed:
        return JSONResponse(status_code=500, content={
            "status": "PARTIAL_FAILURE",
            "bundleId": bundle.bundleId,
            "applied": applied,
            "failed": failed,
            "skipped": skipped,
        })

    return {
        "status": "SUCCESS",
        "bundleId": bundle.bundleId,
        "missionId": bundle.missionId,
        "applied": applied,
    }


@app.get("/health")
def health():
    return {"status": "ok"}
