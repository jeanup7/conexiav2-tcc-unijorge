import io
from PIL import Image


def png_bytes():
    output = io.BytesIO()
    Image.new('RGB', (4, 4), 'blue').save(output, format='PNG')
    return output.getvalue()
