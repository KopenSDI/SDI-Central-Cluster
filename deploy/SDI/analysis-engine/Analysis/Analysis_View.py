# Analysis/Analysis_View.py

import logging
import threading
import uvicorn
from fastapi import FastAPI, Query
from pydantic import BaseModel
from datetime import datetime
import os
import grpc
from concurrent import futures

# gRPC를 위한 임포트 - 실제 프로젝트의 경로에 맞게 수정해야 할 수 있습니다.
# 예: from Protos import analysis_pb2, analysis_pb2_grpc
# 이 부분은 현재 파일 구조를 알 수 없어 일반적인 형태로 작성했습니다.
# 만약 gRPC 서비스 클래스가 다른 곳에 있다면 해당 클래스를 임포트해야 합니다.

# gRPC 서비스 구현체 (Servicer) - 실제 비즈니스 로직을 연결하는 부분
# 이 클래스는 이미 프로젝트 내 다른 곳에 존재할 수 있습니다.
class AnalysisServicer: # (analysis_pb2_grpc.AnalysisServiceServicer):
    def __init__(self, controller):
        self.controller = controller
    
    # 여기에 gRPC 요청을 처리하는 실제 메서드들을 구현합니다.
    # 예: def AnalyzeDevice(self, request, context):
    #        ...
    #        return analysis_pb2.AnalysisResponse(...)


# ========================================================================================
# AnalysisView 클래스 (gRPC + REST)
# ========================================================================================
class AnalysisView:
    def __init__(self, analysis_controller):
        self.controller = analysis_controller
        self.rest_app = self._make_rest_app()
        self.grpc_server = None  # gRPC 서버 인스턴스를 저장할 변수

    # --- gRPC 서버 관련 메서드 ---
    def start_grpc_server(self, port: int, max_workers: int = 10):
        """gRPC 서버를 생성하고 시작합니다."""
        try:
            self.grpc_server = grpc.server(futures.ThreadPoolExecutor(max_workers=max_workers))
            
            # gRPC 서비스 구현체를 서버에 추가합니다.
            # 아래 라인은 실제 프로젝트의 Servicer와 pb2_grpc 모듈에 맞게 수정해야 합니다.
            # analysis_pb2_grpc.add_AnalysisServiceServicer_to_server(
            #     AnalysisServicer(self.controller), self.grpc_server
            # )
            
            self.grpc_server.add_insecure_port(f'[::]:{port}')
            self.grpc_server.start()
            logging.info(f"gRPC 서버가 포트 {port}에서 시작되었습니다.")
            return self.grpc_server
        except Exception as e:
            logging.error(f"gRPC 서버 시작 실패: {e}")
            raise  # 에러를 다시 발생시켜 main.py에서 처리하도록 함

    def stop_grpc_server(self):
        """gRPC 서버를 안전하게 중지합니다."""
        if self.grpc_server:
            logging.info("gRPC 서버 중지 시도...")
            self.grpc_server.stop(grace=5)  # 5초간 대기 후 종료
            logging.info("gRPC 서버 중지 완료.")

    def wait_for_termination(self):
        """gRPC 서버가 종료될 때까지 대기합니다."""
        if self.grpc_server:
            self.grpc_server.wait_for_termination()
            
    # --- REST API 서버 관련 메서드 ---
    def _make_rest_app(self):
        app = FastAPI()

        @app.get("/health")
        def health():
            return {"ok": True}

        @app.get("/api/scores", response_model=ScoresResponse)
        def api_scores():
            acc = int(os.getenv("ACCURACY_SCORE", "80"))
            lat = int(os.getenv("LATENCY_SCORE", "120"))
            ene = int(os.getenv("ENERGY_SCORE", "200"))
            return ScoresResponse(
                success=True,
                accuracy_score=acc,
                latency_score=lat,
                energy_score=ene,
                timestamp=datetime.utcnow().isoformat() + "Z",
                message="ok",
            )

        @app.get("/api/ale-weights", response_model=ALEWeightsResponse)
        def api_ale_weights(
            device_id: str | None = None,
            device_ids: list[str] = Query(default=[])
        ):
            target_ids = device_ids[:] if device_ids else []
            if device_id and device_id not in target_ids:
                target_ids.append(device_id)

            ale_list = []
            failed = []

            try:
                if not target_ids:
                    all_devices = self.controller.get_all_devices()
                    target_ids = [d.get("device_id") for d in all_devices.get("devices", [])]

                if not target_ids:
                    ale_list.append(ALEScoreData(
                        device_id="default",
                        accuracy_score=90.0,
                        latency_score=10.0,
                        energy_score=70.0,
                        calculation_timestamp=datetime.utcnow().isoformat() + "Z",
                    ))
                else:
                    result = self.controller.get_ale_scores_for_devices(target_ids)
                    ale_list = [ALEScoreData(**s) for s in result.get('ale_scores', [])]
                    failed = result.get('failed_devices', [])

            except Exception as e:
                return ALEWeightsResponse(
                    success=False,
                    message=f"error: {e}",
                    total_devices=0,
                    ale_scores=[],
                    failed_devices=target_ids or [],
                )

            return ALEWeightsResponse(
                success=True,
                message="ok",
                total_devices=len(ale_list),
                ale_scores=ale_list,
                failed_devices=failed,
            )

        @app.post("/api/weighted-score", response_model=WeightedScoreResponse)
        def api_weighted_score(req: WeightedScoreRequest):
            """
            외부에서 들어온 실측 A/L/E 값(0-1000)에 디바이스별 가중치를 적용해
            최종 가중 점수를 계산한다. (proto CalculateWeightedScore 의 REST 대응 엔드포인트)
            """
            try:
                r = self.controller.calculate_weighted_score(
                    req.device_id,
                    req.accuracy_value,
                    req.latency_value,
                    req.energy_value,
                )
            except Exception as e:
                return WeightedScoreResponse(success=False, message=f"error: {e}", result=None)

            if not r.get("success"):
                return WeightedScoreResponse(
                    success=False, message=r.get("message", "error"), result=None
                )
            return WeightedScoreResponse(
                success=True,
                message=r.get("message", "ok"),
                result=WeightedScoreData(**r["result"]),
            )

        return app

    def start_rest_server_in_thread(self, host="0.0.0.0", port=5000):
        """ REST 서버를 별도의 스레드에서 실행 """
        th = threading.Thread(
            target=lambda: uvicorn.run(self.rest_app, host=host, port=port, log_level="info"),
            daemon=True,
            name="rest-gateway",
        )
        th.start()
        logging.info(f"REST 게이트웨이가 http://{host}:{port} 에서 시작되었습니다.")
        return th

# --- Pydantic 스키마 정의 ---
class ScoresResponse(BaseModel):
    success: bool
    accuracy_score: int
    latency_score: int
    energy_score: int
    timestamp: str
    message: str | None = None

class ALEScoreData(BaseModel):
    device_id: str
    accuracy_score: float
    latency_score: float
    energy_score: float
    calculation_timestamp: str

class ALEWeightsResponse(BaseModel):
    success: bool
    message: str
    total_devices: int
    ale_scores: list[ALEScoreData]
    failed_devices: list[str]

# --- 가중 점수(WeightedScore) 스키마 : proto CalculateWeightedScore 대응 ---
class WeightedScoreRequest(BaseModel):
    device_id: str
    accuracy_value: float  # 0-1000
    latency_value: float   # 0-1000
    energy_value: float    # 0-1000
    time_range: str | None = "-24h"

class WeightedScoreData(BaseModel):
    device_id: str
    accuracy_score: float
    latency_score: float
    energy_score: float
    weighted_score: float
    score_grade: str
    calculation_timestamp: str
    weights_used: dict | None = None

class WeightedScoreResponse(BaseModel):
    success: bool
    message: str
    result: WeightedScoreData | None = None