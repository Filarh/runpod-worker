# Stage 1: Imagen base con dependencias comunes
FROM nvidia/cuda:12.6.3-cudnn-runtime-ubuntu22.04 AS base

# Evita prompts durante instalación
ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_PREFER_BINARY=1
ENV PYTHONUNBUFFERED=1
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

# Instala herramientas básicas (Python, git, wget)
RUN apt-get update && apt-get install -y \
    python3.11 \
    python3-pip \
    git \
    wget \
    libgl1 \
    && ln -sf /usr/bin/python3.11 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip \
    && apt-get autoremove -y && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

# Instala uv
RUN pip install uv

# Instala comfy-cli
RUN uv pip install comfy-cli --system

# Instala ComfyUI
RUN /usr/bin/yes | comfy --workspace /comfyui install --version 0.3.30 --cuda-version 12.6 --nvidia

# Directorio de trabajo para ComfyUI
WORKDIR /comfyui

# Añadir configuración para soporte de volumen de red (si tienes este archivo en src/)
ADD src/extra_model_paths.yaml ./

# Volver a root para handler
WORKDIR /

# Instala dependencias Python para RunPod
RUN uv pip install runpod requests websocket-client --system

# Añade código de aplicación y scripts necesarios (handler.py requerido para RunPod Serverless)
ADD src/start.sh handler.py test_input.json ./
RUN chmod +x /start.sh

# Comando inicial del contenedor
CMD ["/start.sh"]

# --------------------------------------------
# Stage 2: Descargar modelos (personalizado)
FROM base AS downloader

ARG HUGGINGFACE_ACCESS_TOKEN

# Directorio de trabajo para modelos
WORKDIR /comfyui

# Crea directorios necesarios
RUN mkdir -p models/checkpoints models/vae models/unet models/clip

# Descarga modelo personalizado claramente desde CivitAI y modelos adicionales desde HuggingFace
RUN wget -q -O models/checkpoints/realDream_flux1v1.safetensors "https://civitai.com/api/download/models/1703341?type=Model&format=SafeTensor&size=full&fp=fp8" && \
    wget -q -O models/clip/clip_l.safetensors "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors" && \
    wget -q -O models/clip/t5xxl_fp8_e4m3fn.safetensors "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors" && \
    wget -q --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" -O models/vae/ae.safetensors "https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/ae.safetensors"

# --------------------------------------------
# Stage 3: Imagen final (copia modelos descargados)
FROM base AS final

COPY --from=downloader /comfyui/models /comfyui/models
