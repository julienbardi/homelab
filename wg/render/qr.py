from typing import Dict, cast
from qrcode.image.base import BaseImage
import qrcode

ERROR_CORRECT_Q: int = cast(int,qrcode.constants.ERROR_CORRECT_Q)

def render_client_qr_codes(
    client_configs: Dict[str, str],
) -> Dict[str, BaseImage]:
    """
    Returns:
        peer_id -> QR code image object

    The QR encodes the full WireGuard client config text.
    """
    images: Dict[str, BaseImage] = {}

    for peer_id, cfg in client_configs.items():
        images[peer_id] = _make_qr(cfg)

    return images


def _make_qr(text: str) -> BaseImage:
    qr = qrcode.QRCode(
        version=None,  # automatic size
        error_correction=ERROR_CORRECT_Q,
        box_size=10,
        border=4,
    )
    qr.add_data(text)
    qr.make(fit=True)
    return qr.make_image(fill_color="black", back_color="white")
