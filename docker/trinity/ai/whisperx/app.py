import io
import tempfile
import gc

from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import HTMLResponse, JSONResponse

import whisperx

app = FastAPI()

# Configuration (all CPU)
MODEL_NAME   = "large-v2"
DEVICE       = "cpu"
COMPUTE_TYPE = "int8"    # best trade-off for CPU
BATCH_SIZE   = 8         # tune this for your CPU

# Load ASR model once at startup
model = whisperx.load_model(
    MODEL_NAME,
    device=DEVICE,
    compute_type=COMPUTE_TYPE
)

@app.get("/", response_class=HTMLResponse)
async def homepage():
    return """
    <html>
      <head><title>WhisperX CPU Transcribe</title></head>
      <body>
        <h1>Upload Audio for Transcription</h1>
        <form action="/transcribe" enctype="multipart/form-data" method="post">
          <input type="file" name="file" accept="audio/*"/><br/><br/>
          <button type="submit">Transcribe</button>
        </form>
      </body>
    </html>
    """

@app.post("/transcribe")
async def transcribe(file: UploadFile = File(...)):
    # Validate file extension
    ext = file.filename.rsplit(".", 1)[-1].lower()
    if ext not in {"wav", "mp3", "flac", "m4a"}:
        raise HTTPException(400, "Unsupported file type")

    # Save uploaded file to temp
    with tempfile.NamedTemporaryFile(suffix=f".{ext}") as tmp:
        tmp.write(await file.read())
        tmp.flush()

        # Load audio (may return extra, so slice)
        audio_tuple = whisperx.load_audio(tmp.name, sr=16000)
        audio = audio_tuple[0]

        # Perform transcription
        result = model.transcribe(
            audio,
            batch_size=BATCH_SIZE,
            language=None    # detect automatically
        )

        # Alignment step
        align_model, metadata = whisperx.load_align_model(
            language_code=result["language"],
            device=DEVICE
        )
        result = whisperx.align(
            result["segments"],
            align_model,
            metadata,
            audio,
            DEVICE,
            return_char_alignments=False
        )

        # Clean up the aligner to free RAM
        del align_model
        gc.collect()

    return JSONResponse({
        "language": result["language"],
        "segments": result["segments"]
    })
