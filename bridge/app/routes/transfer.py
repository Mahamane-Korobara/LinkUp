"""Routes de transfert de fichiers chunké (S4.J1).

Toutes protégées par le token Bearer (cf. ADR-002) : seul Laravel/le tél
authentifié peut pousser des chunks. Le payload du chunk est le corps brut de
la requête ; les métadonnées passent par des headers `X-Transfer-*`.

- POST   /transfer/upload            → écrit un chunk (vérifie son SHA-256)
- GET    /transfer/{id}/status       → liste des chunks reçus (reprise)
- POST   /transfer/{id}/finalize     → recompose + vérifie SHA-256 global
- DELETE /transfer/{id}              → annule, nettoie le staging
"""

from typing import Annotated

from fastapi import APIRouter, Depends, Header, HTTPException, Request, status

from app.deps import get_transfer_service, require_transfer_auth
from app.services.transfer import TransferError, TransferService

router = APIRouter(
    prefix="/transfer",
    tags=["transfer"],
    dependencies=[Depends(require_transfer_auth)],
)

ServiceDep = Annotated[TransferService, Depends(get_transfer_service)]


@router.post("/upload")
async def upload_chunk(
    request: Request,
    service: ServiceDep,
    transfer_id: Annotated[str, Header(alias="X-Transfer-Id")],
    chunk_index: Annotated[int, Header(alias="X-Chunk-Index")],
    chunk_sha256: Annotated[str, Header(alias="X-Chunk-Sha256")],
) -> dict:
    data = await request.body()
    if not data:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Chunk vide")
    try:
        service.save_chunk(transfer_id, chunk_index, data, chunk_sha256)
    except TransferError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return {"ok": True, "index": chunk_index, "size": len(data)}


@router.get("/{transfer_id}/status")
def transfer_status(transfer_id: str, service: ServiceDep) -> dict:
    try:
        received = service.received_chunks(transfer_id)
    except TransferError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    return {"transfer_id": transfer_id, "received_chunks": received}


@router.post("/{transfer_id}/finalize")
def finalize_transfer(
    transfer_id: str,
    service: ServiceDep,
    filename: Annotated[str, Header(alias="X-Transfer-Filename")],
    total_chunks: Annotated[int, Header(alias="X-Transfer-Total-Chunks")],
    sha256: Annotated[str, Header(alias="X-Transfer-Sha256")],
) -> dict:
    try:
        dest = service.finalize(transfer_id, filename, total_chunks, sha256)
    except TransferError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return {"ok": True, "path": str(dest), "filename": dest.name, "size": dest.stat().st_size}


@router.delete("/{transfer_id}")
def cancel_transfer(transfer_id: str, service: ServiceDep) -> dict:
    try:
        service.cleanup(transfer_id)
    except TransferError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    return {"ok": True}
