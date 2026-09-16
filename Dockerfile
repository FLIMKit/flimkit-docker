ARG PYTHON_VERSION=3.14
FROM python:${PYTHON_VERSION}-slim-bookworm

# Tk needs an X server, so every variant carries Xvfb.
RUN apt-get update && apt-get install -y --no-install-recommends \
        xvfb \
        x11-utils \
        tzdata \
        python3-tk \
        libglib2.0-0 \
        libx11-6 \
        libxext6 \
        libxcomposite1 \
        libxdamage1 \
        libxfixes3 \
        libxrandr2 \
        fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

ENV TZ=Etc/UTC \
    MPLCONFIGDIR=/tmp/mpl-cache

# Empty TORCH_INDEX leaves torch out, which is most of the image size.
ARG TORCH_INDEX=
RUN if [ -n "${TORCH_INDEX}" ]; then \
        pip install --no-cache-dir torch torchvision --index-url "${TORCH_INDEX}"; \
    fi

ARG FLIMKIT_VERSION
ARG FLIMKIT_EXTRAS=gui
RUN pip install --no-cache-dir "flimkit[${FLIMKIT_EXTRAS}]==${FLIMKIT_VERSION}"

# Switch the default to flimkit-web-ui==<version> once it is published on PyPI
ARG FLIMKIT_WEB_UI=https://github.com/FLIMKit/flimkit-web-ui/archive/refs/heads/main.zip
RUN pip install --no-cache-dir "${FLIMKIT_WEB_UI}"

RUN mkdir -p /tmp/mpl-cache && chmod 777 /tmp/mpl-cache

# The noVNC desktop view is off by default: its dependency tree (node, ghostscript,
# perl, a second system numpy) adds about 300 MB, and the web UI covers the work.
ARG INCLUDE_DESKTOP=0
RUN if [ "${INCLUDE_DESKTOP}" = "1" ]; then \
        apt-get update && apt-get install -y --no-install-recommends \
            x11vnc fluxbox novnc websockify \
        && rm -rf /var/lib/apt/lists/* \
        && printf '<!doctype html>\n<meta http-equiv="refresh" content="0; url=vnc.html?autoconnect=true&resize=scale&reconnect=true">\n' > /usr/share/novnc/index.html \
        && icon=$(python -c "import flimkit, os; print(os.path.join(os.path.dirname(flimkit.__file__), 'UI', 'icon.png'))") \
        && for ic in /usr/share/novnc/app/images/icons/novnc-*.png; do [ -e "$ic" ] && cp -f "$icon" "$ic"; done; \
    fi

COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

ENV FLIMKIT_WEB_HOST=0.0.0.0 \
    FLIMKIT_WEB_PORT=14500 \
    FLIMKIT_WEB_HEADLESS=1

EXPOSE 14500 14501

HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=3 \
    CMD python -c "import os, urllib.request; urllib.request.urlopen('http://127.0.0.1:' + os.environ['FLIMKIT_WEB_PORT'] + '/healthz', timeout=4)"

ARG FLIMKIT_VERSION
LABEL org.opencontainers.image.title="FLIMKit" \
      org.opencontainers.image.description="FLIMKit with its web UI, served on port 14500" \
      org.opencontainers.image.source="https://github.com/FLIMKit/flimkit-docker" \
      org.opencontainers.image.version="${FLIMKIT_VERSION}" \
      org.opencontainers.image.licenses="MIT"

ENTRYPOINT ["/docker-entrypoint.sh"]
