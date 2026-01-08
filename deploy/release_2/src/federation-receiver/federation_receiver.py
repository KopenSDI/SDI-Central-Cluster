#!/usr/bin/env python3
"""
Federation Receiver for Central Cluster
========================================
Edge Cluster로부터 범용 디바이스 메트릭(SDR/SDA/SDV)을 수신하여 InfluxDB에 저장

API Endpoint: POST /api/v1/federation/metrics
"""

import os
import logging
from datetime import datetime, timezone
from typing import Dict, Any, List, Optional
from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI, HTTPException, Header, Request
from pydantic import BaseModel
from influxdb_client import InfluxDBClient, Point
from influxdb_client.client.write_api import SYNCHRONOUS

# ========================================================================================
# Configuration
# ========================================================================================
INFLUX_URL = os.getenv('INFLUX_URL', 'http://influxdb.keti-monitoring.svc.cluster.local:8086')
INFLUX_TOKEN = os.getenv('INFLUX_TOKEN', 'my-super-secret-token')
INFLUX_ORG = os.getenv('INFLUX_ORG', 'keti')
INFLUX_BUCKET = os.getenv('INFLUX_BUCKET', 'federation')
API_TOKEN = os.getenv('API_TOKEN', 'temp-token-for-testing')

HOST = os.getenv("HOST", "0.0.0.0")
PORT = int(os.getenv("PORT", "8080"))

# 로깅 설정
logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)

# InfluxDB 클라이언트 (전역)
influx_client: Optional[InfluxDBClient] = None
write_api = None


# ========================================================================================
# Pydantic 모델 - 범용 디바이스 스키마
# ========================================================================================

class PowerMetrics(BaseModel):
    type: str = "battery"
    percentage: float = 0.0
    voltage: float = 0.0
    current: float = 0.0
    wh_remaining: float = 0.0
    wh_capacity: float = 0.0
    charging: bool = False
    temperature: float = 0.0


class PositionMetrics(BaseModel):
    x: float = 0.0
    y: float = 0.0
    z: float = 0.0
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    altitude: Optional[float] = None
    heading: float = 0.0
    coordinate_system: str = "local"


class MotionMetrics(BaseModel):
    linear_velocity: float = 0.0
    angular_velocity: float = 0.0
    acceleration_x: float = 0.0
    acceleration_y: float = 0.0
    acceleration_z: float = 0.0
    speed: float = 0.0
    moving: bool = False


class EnvironmentMetrics(BaseModel):
    obstacle_min_distance: float = -1.0
    obstacle_front_distance: float = -1.0
    temperature: Optional[float] = None
    humidity: Optional[float] = None
    wind_speed: Optional[float] = None
    wind_direction: Optional[float] = None


class MissionMetrics(BaseModel):
    task_id: Optional[str] = None
    task_name: Optional[str] = None
    task_status: str = "idle"
    progress: float = 0.0
    waypoints_total: int = 0
    waypoints_completed: int = 0


class HealthMetrics(BaseModel):
    cpu_usage: Optional[float] = None
    memory_usage: Optional[float] = None
    disk_usage: Optional[float] = None
    network_latency: Optional[float] = None
    error_count: int = 0
    last_error: Optional[str] = None


# ========================================================================================
# Cluster Compute Spec (Edge Cluster 전체 컴퓨팅 스펙)
# ========================================================================================

class ClusterPlatformInfo(BaseModel):
    system: str = ""               # "Linux"
    release: str = ""              # "6.14.0-34-generic"
    version: str = ""              # "#34~24.04.1-Ubuntu..."
    machine: str = ""              # "x86_64", "aarch64"
    processor: str = ""


class ClusterCpuSpec(BaseModel):
    cores: int = 0                 # 물리 코어 수
    threads: int = 0               # 논리 스레드 수
    architecture: str = ""         # "x86_64", "aarch64"
    model: str = ""                # "Intel Core i7-10700"
    frequency_mhz: float = 0       # 현재 주파수
    frequency_max_mhz: float = 0   # 최대 주파수
    usage_percent: float = 0       # CPU 사용률


class ClusterMemorySpec(BaseModel):
    total_bytes: int = 0
    total_gb: float = 0
    available_bytes: int = 0
    available_gb: float = 0
    used_bytes: int = 0
    used_gb: float = 0
    usage_percent: float = 0
    swap_total_bytes: int = 0
    swap_used_bytes: int = 0
    swap_usage_percent: float = 0


class ClusterDiskPartition(BaseModel):
    device: str = ""               # "/dev/sda1"
    mountpoint: str = ""           # "/"
    fstype: str = ""               # "ext4"
    total_gb: float = 0
    used_gb: float = 0
    usage_percent: float = 0


class ClusterDiskSpec(BaseModel):
    type: str = "unknown"          # "SSD", "HDD", "NVMe SSD"
    total_bytes: int = 0
    total_gb: float = 0
    available_bytes: int = 0
    available_gb: float = 0
    used_bytes: int = 0
    used_gb: float = 0
    usage_percent: float = 0
    partitions: List[ClusterDiskPartition] = []


class ClusterGpuDevice(BaseModel):
    index: int = 0
    name: str = ""                 # "NVIDIA RTX 3080"
    memory_total_mb: int = 0
    memory_used_mb: int = 0
    memory_free_mb: int = 0
    utilization_percent: int = 0
    temperature_c: int = 0


class ClusterGpuSpec(BaseModel):
    available: bool = False
    count: int = 0
    driver_version: Optional[str] = None   # "535.154.05"
    cuda_version: Optional[str] = None     # "12.2"
    devices: List[ClusterGpuDevice] = []


class ClusterNpuSpec(BaseModel):
    available: bool = False
    type: Optional[str] = None     # "Intel Movidius", "Google Coral TPU", "Rockchip RKNN"
    name: Optional[str] = None
    model: Optional[str] = None
    devices: List[Dict[str, Any]] = []


class ClusterMlFrameworks(BaseModel):
    python_version: str = ""
    tensorflow: Optional[str] = None
    tensorflow_gpu: bool = False
    pytorch: Optional[str] = None
    pytorch_cuda: Optional[str] = None
    cuda_available: bool = False
    cudnn_version: Optional[str] = None
    onnx: Optional[str] = None
    onnxruntime: Optional[str] = None
    opencv: Optional[str] = None
    numpy: Optional[str] = None
    scikit_learn: Optional[str] = None


class ClusterRuntimeInfo(BaseModel):
    container_runtime: Optional[str] = None  # "docker", "containerd"
    kubernetes_version: Optional[str] = None
    docker_version: Optional[str] = None
    containerd_version: Optional[str] = None


class ClusterComputeSpec(BaseModel):
    """Edge Cluster 전체 컴퓨팅 스펙"""
    hostname: str = ""
    platform: ClusterPlatformInfo = ClusterPlatformInfo()
    cpu: ClusterCpuSpec = ClusterCpuSpec()
    memory: ClusterMemorySpec = ClusterMemorySpec()
    disk: ClusterDiskSpec = ClusterDiskSpec()
    gpu: ClusterGpuSpec = ClusterGpuSpec()
    npu: ClusterNpuSpec = ClusterNpuSpec()
    ml_frameworks: ClusterMlFrameworks = ClusterMlFrameworks()
    runtime: ClusterRuntimeInfo = ClusterRuntimeInfo()


# ========================================================================================
# Device Compute Metrics (CPU, Memory, Disk, GPU, NPU) - 디바이스 레벨
# ========================================================================================

class CpuInfo(BaseModel):
    cores: int = 0
    model: Optional[str] = None
    architecture: Optional[str] = None
    frequency_mhz: float = 0.0
    usage_percent: float = 0.0


class MemoryInfo(BaseModel):
    total_bytes: int = 0
    available_bytes: int = 0
    used_bytes: int = 0
    usage_percent: float = 0.0


class DiskInfo(BaseModel):
    type: Optional[str] = None  # SSD, HDD, NVMe, eMMC
    total_bytes: int = 0
    available_bytes: int = 0
    used_bytes: int = 0
    usage_percent: float = 0.0


class GpuInfo(BaseModel):
    available: bool = False
    name: Optional[str] = None
    model: Optional[str] = None
    memory_total_bytes: int = 0
    memory_used_bytes: int = 0
    memory_usage_percent: float = 0.0
    utilization_percent: float = 0.0


class NpuInfo(BaseModel):
    available: bool = False
    name: Optional[str] = None
    model: Optional[str] = None
    utilization_percent: float = 0.0


class ComputeMetrics(BaseModel):
    cpu: CpuInfo = CpuInfo()
    memory: MemoryInfo = MemoryInfo()
    disk: DiskInfo = DiskInfo()
    gpu: GpuInfo = GpuInfo()
    npu: NpuInfo = NpuInfo()


class UniversalDevice(BaseModel):
    """범용 디바이스 스키마 - SDR/SDA/SDV/UNKNOWN 지원"""
    device_id: str
    device_type: str = "UNKNOWN"  # SDR, SDA, SDV, UNKNOWN
    device_model: str = "unknown"
    cluster_id: str = ""
    timestamp: str = ""
    status: str = "online"  # online, offline, error, maintenance

    power: PowerMetrics = PowerMetrics()
    position: PositionMetrics = PositionMetrics()
    motion: MotionMetrics = MotionMetrics()
    environment: EnvironmentMetrics = EnvironmentMetrics()
    sensors: Dict[str, Any] = {}
    mission: MissionMetrics = MissionMetrics()
    health: HealthMetrics = HealthMetrics()
    compute: ComputeMetrics = ComputeMetrics()
    custom: Dict[str, Any] = {}
    last_seen: Optional[str] = None


class DeviceMetrics(BaseModel):
    device_count: int = 0
    devices: List[UniversalDevice] = []


class NodeInfo(BaseModel):
    name: str
    ready: bool = True
    architecture: str = "amd64"
    role: str = "worker"
    cpu_capacity_millicores: int = 0
    memory_capacity_bytes: int = 0
    cpu_allocatable_millicores: int = 0
    memory_allocatable_bytes: int = 0
    labels: Dict[str, str] = {}


class ClusterMetrics(BaseModel):
    node_count: int = 0
    nodes: List[NodeInfo] = []
    total_cpu_capacity_millicores: int = 0
    total_memory_capacity_bytes: int = 0
    total_cpu_allocatable_millicores: int = 0
    total_memory_allocatable_bytes: int = 0


class PodInfo(BaseModel):
    name: str
    namespace: str = "default"
    phase: str = "Running"
    node: str = ""
    cpu_request_millicores: int = 0
    memory_request_bytes: int = 0
    cpu_limit_millicores: int = 0
    memory_limit_bytes: int = 0
    labels: Dict[str, str] = {}


class DeploymentInfo(BaseModel):
    name: str
    namespace: str = "default"
    replicas_desired: int = 1
    replicas_ready: int = 0
    replicas_available: int = 0
    labels: Dict[str, str] = {}


class WorkloadMetrics(BaseModel):
    pod_count: int = 0
    pods: List[PodInfo] = []
    deployment_count: int = 0
    deployments: List[DeploymentInfo] = []


class FederationPayload(BaseModel):
    """Edge Cluster에서 전송하는 전체 페이로드"""
    cluster_id: str
    cluster_name: str = ""
    timestamp: str = ""
    cluster_compute_spec: Optional[ClusterComputeSpec] = None  # Edge Cluster 컴퓨팅 스펙
    cluster_metrics: Optional[ClusterMetrics] = None
    workload_metrics: Optional[WorkloadMetrics] = None
    device_metrics: Optional[DeviceMetrics] = None


# ========================================================================================
# InfluxDB 저장 함수
# ========================================================================================

def store_cluster_compute_spec(cluster_id: str, spec: ClusterComputeSpec, timestamp: datetime):
    """클러스터 컴퓨팅 스펙 InfluxDB 저장"""

    # 1. 클러스터 플랫폼 정보
    point = (
        Point("cluster_platform")
        .tag("cluster_id", cluster_id)
        .tag("hostname", spec.hostname)
        .field("system", spec.platform.system)
        .field("release", spec.platform.release)
        .field("machine", spec.platform.machine)
        .field("processor", spec.platform.processor)
        .time(timestamp)
    )
    write_api.write(bucket=INFLUX_BUCKET, record=point)

    # 2. 클러스터 CPU 스펙
    point = (
        Point("cluster_cpu_spec")
        .tag("cluster_id", cluster_id)
        .tag("architecture", spec.cpu.architecture)
        .field("cores", spec.cpu.cores)
        .field("threads", spec.cpu.threads)
        .field("model", spec.cpu.model)
        .field("frequency_mhz", spec.cpu.frequency_mhz)
        .field("frequency_max_mhz", spec.cpu.frequency_max_mhz)
        .field("usage_percent", spec.cpu.usage_percent)
        .time(timestamp)
    )
    write_api.write(bucket=INFLUX_BUCKET, record=point)

    # 3. 클러스터 메모리 스펙
    point = (
        Point("cluster_memory_spec")
        .tag("cluster_id", cluster_id)
        .field("total_bytes", spec.memory.total_bytes)
        .field("total_gb", spec.memory.total_gb)
        .field("available_bytes", spec.memory.available_bytes)
        .field("available_gb", spec.memory.available_gb)
        .field("used_bytes", spec.memory.used_bytes)
        .field("used_gb", spec.memory.used_gb)
        .field("usage_percent", spec.memory.usage_percent)
        .field("swap_total_bytes", spec.memory.swap_total_bytes)
        .field("swap_used_bytes", spec.memory.swap_used_bytes)
        .field("swap_usage_percent", spec.memory.swap_usage_percent)
        .time(timestamp)
    )
    write_api.write(bucket=INFLUX_BUCKET, record=point)

    # 4. 클러스터 디스크 스펙
    point = (
        Point("cluster_disk_spec")
        .tag("cluster_id", cluster_id)
        .tag("disk_type", spec.disk.type)
        .field("total_bytes", spec.disk.total_bytes)
        .field("total_gb", spec.disk.total_gb)
        .field("available_bytes", spec.disk.available_bytes)
        .field("available_gb", spec.disk.available_gb)
        .field("used_bytes", spec.disk.used_bytes)
        .field("used_gb", spec.disk.used_gb)
        .field("usage_percent", spec.disk.usage_percent)
        .time(timestamp)
    )
    write_api.write(bucket=INFLUX_BUCKET, record=point)

    # 5. 클러스터 GPU 스펙 (가용한 경우)
    point = (
        Point("cluster_gpu_spec")
        .tag("cluster_id", cluster_id)
        .field("available", 1 if spec.gpu.available else 0)
        .field("count", spec.gpu.count)
        .time(timestamp)
    )
    if spec.gpu.driver_version:
        point = point.field("driver_version", spec.gpu.driver_version)
    if spec.gpu.cuda_version:
        point = point.field("cuda_version", spec.gpu.cuda_version)
    write_api.write(bucket=INFLUX_BUCKET, record=point)

    # GPU 디바이스별 정보
    for gpu_dev in spec.gpu.devices:
        point = (
            Point("cluster_gpu_device")
            .tag("cluster_id", cluster_id)
            .tag("gpu_index", str(gpu_dev.index))
            .tag("gpu_name", gpu_dev.name)
            .field("memory_total_mb", gpu_dev.memory_total_mb)
            .field("memory_used_mb", gpu_dev.memory_used_mb)
            .field("memory_free_mb", gpu_dev.memory_free_mb)
            .field("utilization_percent", gpu_dev.utilization_percent)
            .field("temperature_c", gpu_dev.temperature_c)
            .time(timestamp)
        )
        write_api.write(bucket=INFLUX_BUCKET, record=point)

    # 6. 클러스터 NPU 스펙
    point = (
        Point("cluster_npu_spec")
        .tag("cluster_id", cluster_id)
        .field("available", 1 if spec.npu.available else 0)
        .time(timestamp)
    )
    if spec.npu.type:
        point = point.field("npu_type", spec.npu.type)
    if spec.npu.name:
        point = point.field("name", spec.npu.name)
    if spec.npu.model:
        point = point.field("model", spec.npu.model)
    write_api.write(bucket=INFLUX_BUCKET, record=point)

    # 7. ML 프레임워크 정보
    point = (
        Point("cluster_ml_frameworks")
        .tag("cluster_id", cluster_id)
        .field("python_version", spec.ml_frameworks.python_version)
        .field("tensorflow_gpu", 1 if spec.ml_frameworks.tensorflow_gpu else 0)
        .field("cuda_available", 1 if spec.ml_frameworks.cuda_available else 0)
        .time(timestamp)
    )
    if spec.ml_frameworks.tensorflow:
        point = point.field("tensorflow", spec.ml_frameworks.tensorflow)
    if spec.ml_frameworks.pytorch:
        point = point.field("pytorch", spec.ml_frameworks.pytorch)
    if spec.ml_frameworks.pytorch_cuda:
        point = point.field("pytorch_cuda", spec.ml_frameworks.pytorch_cuda)
    if spec.ml_frameworks.onnx:
        point = point.field("onnx", spec.ml_frameworks.onnx)
    if spec.ml_frameworks.opencv:
        point = point.field("opencv", spec.ml_frameworks.opencv)
    if spec.ml_frameworks.numpy:
        point = point.field("numpy", spec.ml_frameworks.numpy)
    write_api.write(bucket=INFLUX_BUCKET, record=point)

    # 8. 런타임 정보
    point = Point("cluster_runtime").tag("cluster_id", cluster_id).time(timestamp)
    if spec.runtime.container_runtime:
        point = point.field("container_runtime", spec.runtime.container_runtime)
    if spec.runtime.kubernetes_version:
        point = point.field("kubernetes_version", spec.runtime.kubernetes_version)
    if spec.runtime.docker_version:
        point = point.field("docker_version", spec.runtime.docker_version)
    if spec.runtime.containerd_version:
        point = point.field("containerd_version", spec.runtime.containerd_version)
    write_api.write(bucket=INFLUX_BUCKET, record=point)


def store_cluster_metrics(cluster_id: str, metrics: ClusterMetrics, timestamp: datetime):
    """클러스터 메트릭 InfluxDB 저장"""

    # 클러스터 요약
    point = (
        Point("cluster_summary")
        .tag("cluster_id", cluster_id)
        .field("node_count", metrics.node_count)
        .field("total_cpu_capacity", metrics.total_cpu_capacity_millicores)
        .field("total_memory_capacity", metrics.total_memory_capacity_bytes)
        .field("total_cpu_allocatable", metrics.total_cpu_allocatable_millicores)
        .field("total_memory_allocatable", metrics.total_memory_allocatable_bytes)
        .time(timestamp)
    )
    write_api.write(bucket=INFLUX_BUCKET, record=point)

    # 각 노드별 상태
    for node in metrics.nodes:
        point = (
            Point("node_status")
            .tag("cluster_id", cluster_id)
            .tag("node_name", node.name)
            .tag("role", node.role)
            .tag("architecture", node.architecture)
            .field("ready", 1 if node.ready else 0)
            .field("cpu_capacity", node.cpu_capacity_millicores)
            .field("memory_capacity", node.memory_capacity_bytes)
            .field("cpu_allocatable", node.cpu_allocatable_millicores)
            .field("memory_allocatable", node.memory_allocatable_bytes)
            .time(timestamp)
        )
        write_api.write(bucket=INFLUX_BUCKET, record=point)


def store_workload_metrics(cluster_id: str, metrics: WorkloadMetrics, timestamp: datetime):
    """워크로드 메트릭 InfluxDB 저장"""

    # 워크로드 요약
    point = (
        Point("workload_summary")
        .tag("cluster_id", cluster_id)
        .field("pod_count", metrics.pod_count)
        .field("deployment_count", metrics.deployment_count)
        .time(timestamp)
    )
    write_api.write(bucket=INFLUX_BUCKET, record=point)

    # Pod 메트릭
    for pod in metrics.pods:
        point = (
            Point("pod_metrics")
            .tag("cluster_id", cluster_id)
            .tag("pod_name", pod.name)
            .tag("namespace", pod.namespace)
            .tag("node", pod.node)
            .tag("phase", pod.phase)
            .field("cpu_request", pod.cpu_request_millicores)
            .field("memory_request", pod.memory_request_bytes)
            .field("cpu_limit", pod.cpu_limit_millicores)
            .field("memory_limit", pod.memory_limit_bytes)
            .time(timestamp)
        )
        write_api.write(bucket=INFLUX_BUCKET, record=point)

    # Deployment 메트릭
    for deploy in metrics.deployments:
        point = (
            Point("deployment_metrics")
            .tag("cluster_id", cluster_id)
            .tag("deployment_name", deploy.name)
            .tag("namespace", deploy.namespace)
            .field("replicas_desired", deploy.replicas_desired)
            .field("replicas_ready", deploy.replicas_ready)
            .field("replicas_available", deploy.replicas_available)
            .time(timestamp)
        )
        write_api.write(bucket=INFLUX_BUCKET, record=point)


def store_device_metrics(cluster_id: str, metrics: DeviceMetrics, timestamp: datetime):
    """범용 디바이스 메트릭 InfluxDB 저장"""

    for device in metrics.devices:
        device_tags = {
            "cluster_id": cluster_id,
            "device_id": device.device_id,
            "device_type": device.device_type,
            "device_model": device.device_model
        }

        # 1. 디바이스 상태
        point = (
            Point("device_status")
            .tag("cluster_id", cluster_id)
            .tag("device_id", device.device_id)
            .tag("device_type", device.device_type)
            .tag("device_model", device.device_model)
            .field("status", device.status)
            .field("online", 1 if device.status == "online" else 0)
            .time(timestamp)
        )
        write_api.write(bucket=INFLUX_BUCKET, record=point)

        # 2. 전원 메트릭
        point = (
            Point("device_power")
            .tag("cluster_id", cluster_id)
            .tag("device_id", device.device_id)
            .tag("device_type", device.device_type)
            .field("type", device.power.type)
            .field("percentage", device.power.percentage)
            .field("voltage", device.power.voltage)
            .field("current", device.power.current)
            .field("wh_remaining", device.power.wh_remaining)
            .field("wh_capacity", device.power.wh_capacity)
            .field("charging", 1 if device.power.charging else 0)
            .field("temperature", device.power.temperature)
            .time(timestamp)
        )
        write_api.write(bucket=INFLUX_BUCKET, record=point)

        # 3. 위치 메트릭
        point = (
            Point("device_position")
            .tag("cluster_id", cluster_id)
            .tag("device_id", device.device_id)
            .tag("device_type", device.device_type)
            .tag("coordinate_system", device.position.coordinate_system)
            .field("x", device.position.x)
            .field("y", device.position.y)
            .field("z", device.position.z)
            .field("heading", device.position.heading)
            .time(timestamp)
        )
        # GPS 좌표가 있으면 추가
        if device.position.latitude is not None:
            point = point.field("latitude", device.position.latitude)
        if device.position.longitude is not None:
            point = point.field("longitude", device.position.longitude)
        if device.position.altitude is not None:
            point = point.field("altitude", device.position.altitude)
        write_api.write(bucket=INFLUX_BUCKET, record=point)

        # 4. 모션 메트릭
        point = (
            Point("device_motion")
            .tag("cluster_id", cluster_id)
            .tag("device_id", device.device_id)
            .tag("device_type", device.device_type)
            .field("linear_velocity", device.motion.linear_velocity)
            .field("angular_velocity", device.motion.angular_velocity)
            .field("acceleration_x", device.motion.acceleration_x)
            .field("acceleration_y", device.motion.acceleration_y)
            .field("acceleration_z", device.motion.acceleration_z)
            .field("speed", device.motion.speed)
            .field("moving", 1 if device.motion.moving else 0)
            .time(timestamp)
        )
        write_api.write(bucket=INFLUX_BUCKET, record=point)

        # 5. 환경 메트릭
        point = (
            Point("device_environment")
            .tag("cluster_id", cluster_id)
            .tag("device_id", device.device_id)
            .tag("device_type", device.device_type)
            .field("obstacle_min_distance", device.environment.obstacle_min_distance)
            .field("obstacle_front_distance", device.environment.obstacle_front_distance)
            .time(timestamp)
        )
        if device.environment.temperature is not None:
            point = point.field("temperature", device.environment.temperature)
        if device.environment.humidity is not None:
            point = point.field("humidity", device.environment.humidity)
        if device.environment.wind_speed is not None:
            point = point.field("wind_speed", device.environment.wind_speed)
        if device.environment.wind_direction is not None:
            point = point.field("wind_direction", device.environment.wind_direction)
        write_api.write(bucket=INFLUX_BUCKET, record=point)

        # 6. 미션 메트릭 (task_id가 있을 때만)
        if device.mission.task_id:
            point = (
                Point("device_mission")
                .tag("cluster_id", cluster_id)
                .tag("device_id", device.device_id)
                .tag("device_type", device.device_type)
                .tag("task_id", device.mission.task_id)
                .field("task_name", device.mission.task_name or "")
                .field("task_status", device.mission.task_status)
                .field("progress", device.mission.progress)
                .field("waypoints_total", device.mission.waypoints_total)
                .field("waypoints_completed", device.mission.waypoints_completed)
                .time(timestamp)
            )
            write_api.write(bucket=INFLUX_BUCKET, record=point)

        # 7. 헬스 메트릭
        point = Point("device_health").tag("cluster_id", cluster_id).tag("device_id", device.device_id).tag("device_type", device.device_type)
        if device.health.cpu_usage is not None:
            point = point.field("cpu_usage", device.health.cpu_usage)
        if device.health.memory_usage is not None:
            point = point.field("memory_usage", device.health.memory_usage)
        if device.health.disk_usage is not None:
            point = point.field("disk_usage", device.health.disk_usage)
        point = point.field("error_count", device.health.error_count)
        point = point.time(timestamp)
        write_api.write(bucket=INFLUX_BUCKET, record=point)

        # 8. 컴퓨트 메트릭 (CPU, Memory, Disk, GPU, NPU)
        # CPU
        point = (
            Point("device_compute_cpu")
            .tag("cluster_id", cluster_id)
            .tag("device_id", device.device_id)
            .tag("device_type", device.device_type)
            .field("cores", device.compute.cpu.cores)
            .field("frequency_mhz", device.compute.cpu.frequency_mhz)
            .field("usage_percent", device.compute.cpu.usage_percent)
            .time(timestamp)
        )
        if device.compute.cpu.model:
            point = point.field("model", device.compute.cpu.model)
        if device.compute.cpu.architecture:
            point = point.field("architecture", device.compute.cpu.architecture)
        write_api.write(bucket=INFLUX_BUCKET, record=point)

        # Memory
        point = (
            Point("device_compute_memory")
            .tag("cluster_id", cluster_id)
            .tag("device_id", device.device_id)
            .tag("device_type", device.device_type)
            .field("total_bytes", device.compute.memory.total_bytes)
            .field("available_bytes", device.compute.memory.available_bytes)
            .field("used_bytes", device.compute.memory.used_bytes)
            .field("usage_percent", device.compute.memory.usage_percent)
            .time(timestamp)
        )
        write_api.write(bucket=INFLUX_BUCKET, record=point)

        # Disk
        point = (
            Point("device_compute_disk")
            .tag("cluster_id", cluster_id)
            .tag("device_id", device.device_id)
            .tag("device_type", device.device_type)
            .field("total_bytes", device.compute.disk.total_bytes)
            .field("available_bytes", device.compute.disk.available_bytes)
            .field("used_bytes", device.compute.disk.used_bytes)
            .field("usage_percent", device.compute.disk.usage_percent)
            .time(timestamp)
        )
        if device.compute.disk.type:
            point = point.field("disk_type", device.compute.disk.type)
        write_api.write(bucket=INFLUX_BUCKET, record=point)

        # GPU (if available)
        if device.compute.gpu.available:
            point = (
                Point("device_compute_gpu")
                .tag("cluster_id", cluster_id)
                .tag("device_id", device.device_id)
                .tag("device_type", device.device_type)
                .field("available", 1)
                .field("memory_total_bytes", device.compute.gpu.memory_total_bytes)
                .field("memory_used_bytes", device.compute.gpu.memory_used_bytes)
                .field("memory_usage_percent", device.compute.gpu.memory_usage_percent)
                .field("utilization_percent", device.compute.gpu.utilization_percent)
                .time(timestamp)
            )
            if device.compute.gpu.name:
                point = point.field("name", device.compute.gpu.name)
            if device.compute.gpu.model:
                point = point.field("model", device.compute.gpu.model)
            write_api.write(bucket=INFLUX_BUCKET, record=point)

        # NPU (if available)
        if device.compute.npu.available:
            point = (
                Point("device_compute_npu")
                .tag("cluster_id", cluster_id)
                .tag("device_id", device.device_id)
                .tag("device_type", device.device_type)
                .field("available", 1)
                .field("utilization_percent", device.compute.npu.utilization_percent)
                .time(timestamp)
            )
            if device.compute.npu.name:
                point = point.field("name", device.compute.npu.name)
            if device.compute.npu.model:
                point = point.field("model", device.compute.npu.model)
            write_api.write(bucket=INFLUX_BUCKET, record=point)


# ========================================================================================
# FastAPI Application with Lifespan
# ========================================================================================

@asynccontextmanager
async def lifespan(app: FastAPI):
    """애플리케이션 시작/종료 시 InfluxDB 연결 관리"""
    global influx_client, write_api

    # Startup
    logger.info("=" * 60)
    logger.info("Federation Receiver Starting...")
    logger.info(f"  InfluxDB URL: {INFLUX_URL}")
    logger.info(f"  InfluxDB Bucket: {INFLUX_BUCKET}")
    logger.info(f"  Supported Device Types: SDR, SDA, SDV, UNKNOWN")
    logger.info("=" * 60)

    influx_client = InfluxDBClient(url=INFLUX_URL, token=INFLUX_TOKEN, org=INFLUX_ORG)
    write_api = influx_client.write_api(write_options=SYNCHRONOUS)

    # 버킷 확인/생성
    try:
        buckets_api = influx_client.buckets_api()
        bucket = buckets_api.find_bucket_by_name(INFLUX_BUCKET)
        if bucket is None:
            buckets_api.create_bucket(bucket_name=INFLUX_BUCKET, org=INFLUX_ORG)
            logger.info(f"Bucket '{INFLUX_BUCKET}' created")
        else:
            logger.info(f"Bucket '{INFLUX_BUCKET}' exists")
    except Exception as e:
        logger.warning(f"Bucket check failed (ignoring): {e}")

    yield

    # Shutdown
    if influx_client:
        influx_client.close()
    logger.info("Federation Receiver stopped")


app = FastAPI(
    title="Federation Receiver",
    description="Central Cluster Metrics Receiver - SDR/SDA/SDV Universal Schema with Cluster Compute Spec",
    version="2.2.0",
    lifespan=lifespan
)


# ========================================================================================
# API 엔드포인트
# ========================================================================================

@app.get("/health")
async def health_check():
    """헬스 체크"""
    return {"status": "healthy", "timestamp": datetime.now(timezone.utc).isoformat()}


@app.get("/ready")
async def readiness_check():
    """Readiness 체크"""
    if influx_client and write_api:
        return {"ready": True, "version": "2.2.0"}
    return {"ready": False, "message": "InfluxDB not connected"}


@app.post("/api/v1/federation/metrics")
async def receive_metrics(
    payload: FederationPayload,
    request: Request,
    x_cluster_id: Optional[str] = Header(None, alias="X-Cluster-ID"),
    authorization: Optional[str] = Header(None)
):
    """
    Edge Cluster로부터 메트릭 수신
    - SDR (Robot): TurtleBot, AMR
    - SDA (Air): 드론, UAV
    - SDV (Vehicle): AGV, 자율주행차
    """

    # 토큰 검증 (선택)
    if API_TOKEN and authorization:
        token = authorization.replace("Bearer ", "")
        if token != API_TOKEN:
            logger.warning(f"Invalid token from {request.client.host}")
            raise HTTPException(status_code=401, detail="Invalid token")

    cluster_id = x_cluster_id or payload.cluster_id
    client_ip = request.client.host if request.client else "unknown"

    # timestamp 파싱
    try:
        if payload.timestamp:
            timestamp = datetime.fromisoformat(payload.timestamp.replace('Z', '+00:00'))
        else:
            timestamp = datetime.now(timezone.utc)
    except:
        timestamp = datetime.now(timezone.utc)

    try:
        node_count = 0
        pod_count = 0
        device_count = 0

        # 0. 클러스터 컴퓨팅 스펙 저장
        if payload.cluster_compute_spec:
            store_cluster_compute_spec(cluster_id, payload.cluster_compute_spec, timestamp)
            logger.info(f"  [COMPUTE_SPEC] hostname={payload.cluster_compute_spec.hostname}, "
                       f"cpu={payload.cluster_compute_spec.cpu.cores}cores, "
                       f"memory={payload.cluster_compute_spec.memory.total_gb:.1f}GB, "
                       f"gpu={payload.cluster_compute_spec.gpu.available}")

        # 1. 클러스터 메트릭 저장
        if payload.cluster_metrics:
            store_cluster_metrics(cluster_id, payload.cluster_metrics, timestamp)
            node_count = payload.cluster_metrics.node_count

        # 2. 워크로드 메트릭 저장
        if payload.workload_metrics:
            store_workload_metrics(cluster_id, payload.workload_metrics, timestamp)
            pod_count = payload.workload_metrics.pod_count

        # 3. 디바이스 메트릭 저장 (범용 스키마)
        if payload.device_metrics:
            store_device_metrics(cluster_id, payload.device_metrics, timestamp)
            device_count = payload.device_metrics.device_count
            # 디버그: 디바이스 상세 정보 출력
            for dev in payload.device_metrics.devices:
                logger.info(f"  [DEBUG] Device: {dev.device_id} ({dev.device_type})")
                logger.info(f"    power: percentage={dev.power.percentage}, voltage={dev.power.voltage}")
                logger.info(f"    position: x={dev.position.x}, y={dev.position.y}, heading={dev.position.heading}")
                logger.info(f"    motion: speed={dev.motion.speed}, moving={dev.motion.moving}")
                logger.info(f"    compute.cpu: cores={dev.compute.cpu.cores}, usage={dev.compute.cpu.usage_percent}%")

        logger.info(
            f"Received from {cluster_id} ({client_ip}): "
            f"{node_count} nodes, {pod_count} pods, {device_count} devices"
        )

        return {
            "status": "accepted",
            "cluster_id": cluster_id,
            "received_at": datetime.now(timezone.utc).isoformat(),
            "metrics": {
                "nodes": node_count,
                "pods": pod_count,
                "devices": device_count
            }
        }

    except Exception as e:
        logger.exception(f"Error processing metrics from {cluster_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/v1/federation/clusters")
async def get_clusters():
    """등록된 클러스터 목록 조회"""
    try:
        query_api = influx_client.query_api()
        flux = f'''
        from(bucket: "{INFLUX_BUCKET}")
            |> range(start: -1h)
            |> filter(fn: (r) => r._measurement == "cluster_summary")
            |> group(columns: ["cluster_id"])
            |> last()
        '''
        tables = query_api.query(query=flux)

        clusters = {}
        for table in tables:
            for record in table.records:
                cid = record.values.get("cluster_id", "unknown")
                if cid not in clusters:
                    clusters[cid] = {}
                clusters[cid][record.get_field()] = record.get_value()

        return {"clusters": clusters, "count": len(clusters)}
    except Exception as e:
        logger.error(f"Failed to query clusters: {e}")
        return {"clusters": {}, "count": 0, "error": str(e)}


@app.get("/api/v1/federation/devices")
async def get_devices():
    """등록된 디바이스 목록 조회"""
    try:
        query_api = influx_client.query_api()
        flux = f'''
        from(bucket: "{INFLUX_BUCKET}")
            |> range(start: -5m)
            |> filter(fn: (r) => r._measurement == "device_status")
            |> group(columns: ["device_id", "device_type", "device_model"])
            |> last()
        '''
        tables = query_api.query(query=flux)

        devices = {}
        for table in tables:
            for record in table.records:
                did = record.values.get("device_id", "unknown")
                if did not in devices:
                    devices[did] = {
                        "device_type": record.values.get("device_type", "UNKNOWN"),
                        "device_model": record.values.get("device_model", "unknown"),
                        "cluster_id": record.values.get("cluster_id", "unknown")
                    }
                devices[did][record.get_field()] = record.get_value()

        return {"devices": devices, "count": len(devices)}
    except Exception as e:
        logger.error(f"Failed to query devices: {e}")
        return {"devices": {}, "count": 0, "error": str(e)}


@app.get("/api/v1/federation/status")
async def get_status():
    """Federation Receiver 상태 조회"""
    return {
        "service": "federation-receiver",
        "version": "2.2.0",
        "influx_url": INFLUX_URL,
        "influx_bucket": INFLUX_BUCKET,
        "supported_device_types": ["SDR", "SDA", "SDV", "UNKNOWN"],
        "supported_metrics": ["power", "position", "motion", "environment", "sensors", "mission", "health", "compute"],
        "device_compute_components": ["cpu", "memory", "disk", "gpu", "npu"],
        "cluster_compute_spec": ["platform", "cpu", "memory", "disk", "gpu", "npu", "ml_frameworks", "runtime"],
        "status": "running",
        "timestamp": datetime.now(timezone.utc).isoformat()
    }


# ========================================================================================
# Main Entry Point
# ========================================================================================

if __name__ == "__main__":
    uvicorn.run(app, host=HOST, port=PORT, log_level="info")
