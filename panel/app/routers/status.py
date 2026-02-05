"""Status API endpoints"""
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
import psutil

from app.database import get_db
from app.models import Tunnel, Node


router = APIRouter()

VERSION = "0.1.0"


@router.get("/version")
async def get_version():
    """Get panel version from git tag, VERSION file, Docker image label, or environment"""
    import os
    import subprocess
    from pathlib import Path
    
    try:
        result = subprocess.run(
            ["git", "describe", "--tags", "--always", "--dirty"],
            capture_output=True,
            text=True,
            timeout=2,
            cwd="/app"
        )
        if result.returncode == 0:
            git_version = result.stdout.strip()
            if git_version and not git_version.startswith("fatal"):
                version = git_version.split("-")[0].lstrip("v")
                if version and version not in ["next", "latest", "main", "master"]:
                    return {"version": version}
    except:
        pass
    
    version_file = Path("/app/VERSION")
    if version_file.exists():
        try:
            version = version_file.read_text().strip()
            if version and version not in ["next", "latest"]:
                return {"version": version.lstrip("v")}
        except:
            pass
    
    smite_version = os.getenv("SMITE_VERSION", "")
    if smite_version in ["next", "latest"]:
        try:
            import json
            cgroup_path = Path("/proc/self/cgroup")
            if cgroup_path.exists():
                with open(cgroup_path) as f:
                    for line in f:
                        if "docker" in line or "containerd" in line:
                            container_id = line.split("/")[-1].strip()
                            result = subprocess.run(
                                ["docker", "inspect", container_id],
                                capture_output=True,
                                text=True,
                                timeout=2
                            )
                            if result.returncode == 0:
                                data = json.loads(result.stdout)
                                if data and len(data) > 0:
                                    labels = data[0].get("Config", {}).get("Labels", {})
                                    version = labels.get("smite.version") or labels.get("org.opencontainers.image.version", "")
                                    if version and version not in ["next", "latest"]:
                                        return {"version": version.lstrip("v")}
                            break
        except:
            pass
        
        return {"version": smite_version}
    
    if smite_version:
        version = smite_version.lstrip("v")
    else:
        version = VERSION
    
    return {"version": version}


@router.get("")
async def get_status(db: AsyncSession = Depends(get_db)):
    """Get system status"""
    cpu_percent = psutil.cpu_percent(interval=1)
    memory = psutil.virtual_memory()
    
    tunnel_result = await db.execute(select(func.count(Tunnel.id)))
    total_tunnels = tunnel_result.scalar() or 0
    
    active_tunnels_result = await db.execute(
        select(func.count(Tunnel.id)).where(Tunnel.status == "active")
    )
    active_tunnels = active_tunnels_result.scalar() or 0
    
    node_result = await db.execute(select(func.count(Node.id)))
    total_nodes = node_result.scalar() or 0
    
    active_nodes_result = await db.execute(
        select(func.count(Node.id)).where(Node.status == "active")
    )
    active_nodes = active_nodes_result.scalar() or 0
    
    return {
        "system": {
            "cpu_percent": cpu_percent,
            "memory_percent": memory.percent,
            "memory_total_gb": memory.total / (1024**3),
            "memory_used_gb": memory.used / (1024**3),
        },
        "tunnels": {
            "total": total_tunnels,
            "active": active_tunnels,
        },
        "nodes": {
            "total": total_nodes,
            "active": active_nodes,
        }
    }


def _read_net_bytes():
    """Read total rx/tx bytes from /proc/net/dev (sum all interfaces except loopback)."""
    total_rx = total_tx = 0
    try:
        with open("/proc/net/dev") as f:
            for line in f:
                line = line.strip()
                if ":" in line:
                    name, rest = line.split(":", 1)
                    name = name.strip()
                    if name == "lo":
                        continue
                    parts = rest.split()
                    if len(parts) >= 10:
                        total_rx += int(parts[0])
                        total_tx += int(parts[8])
    except Exception:
        pass
    return total_rx, total_tx


@router.get("/traffic")
async def get_traffic():
    """Live traffic: sample /proc/net/dev twice to compute rx/tx rate (bytes per second)."""
    import asyncio
    rx1, tx1 = _read_net_bytes()
    await asyncio.sleep(1)
    rx2, tx2 = _read_net_bytes()
    rx_rate_bps = max(0, rx2 - rx1)
    tx_rate_bps = max(0, tx2 - tx1)
    return {
        "rx_bytes_per_sec": rx_rate_bps,
        "tx_bytes_per_sec": tx_rate_bps,
        "rx_mbps": round(rx_rate_bps * 8 / 1_000_000, 4),
        "tx_mbps": round(tx_rate_bps * 8 / 1_000_000, 4),
    }

