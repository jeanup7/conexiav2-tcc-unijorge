"""Validate actual pixels and discard metadata before persisting user images."""
import base64
import binascii
import io
import warnings
from PIL import Image, UnidentifiedImageError
from security import ApiError, text

MAX_BYTES = 5 * 1024 * 1024
MAX_PIXELS = 16_000_000
FORMATS = {'image/jpeg': 'JPEG', 'image/png': 'PNG', 'image/webp': 'WEBP'}


def normalize(data):
    mime = text(data, 'mime', 1, 40)
    if mime not in FORMATS:
        raise ApiError(400, 'Use imagens JPEG, PNG ou WebP.')
    encoded = text(data, 'data', 1, 7_000_000)
    try:
        content = base64.b64decode(encoded, validate=True)
    except (ValueError, binascii.Error):
        raise ApiError(400, 'Imagem inválida.')
    if not content or len(content) > MAX_BYTES:
        raise ApiError(413, 'Cada imagem deve ter até 5 MB.')
    try:
        with warnings.catch_warnings():
            warnings.simplefilter('error', Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(content)) as image:
                if image.format != FORMATS[mime] or getattr(image, 'n_frames', 1) != 1:
                    raise ApiError(400, 'O formato deve corresponder à imagem, sem animação.')
                width, height = image.size
                if width * height > MAX_PIXELS or max(width, height) > 4096:
                    raise ApiError(400, 'A imagem deve ter até 4096 pixels por lado e 16 milhões de pixels.')
                image.verify()
            with Image.open(io.BytesIO(content)) as image:
                from PIL import ImageOps
                # Apply orientation before stripping GPS, EXIF and embedded comments.
                image = ImageOps.exif_transpose(image)
                mode = 'RGB' if mime == 'image/jpeg' else 'RGBA' if 'A' in image.getbands() or 'transparency' in image.info else 'RGB'
                clean = Image.new(mode, image.size)
                clean.paste(image.convert(mode))
                output = io.BytesIO()
                clean.save(output, format=FORMATS[mime], **({'quality': 85} if mime != 'image/png' else {}))
                result = output.getvalue()
    except ApiError:
        raise
    except (UnidentifiedImageError, OSError, SyntaxError, ValueError, Image.DecompressionBombError, Image.DecompressionBombWarning):
        raise ApiError(400, 'Não foi possível validar esta imagem.')
    if len(result) > MAX_BYTES:
        raise ApiError(413, 'A imagem processada excede 5 MB.')
    return mime, result
