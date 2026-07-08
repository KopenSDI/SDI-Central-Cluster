from fastapi import FastAPI, HTTPException, Request
from .core.enrichment import enrich_manifest
from .core.client import SDIClient
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

@app.get("/health")
def health():
    return {"status": "ok"}
