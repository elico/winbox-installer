OUTPUT_DIR ?= dist
INSTALLER_NAME ?= winbox-tools-setup.exe


IMG_C    ?= winbox-build-c
IMG_GO   ?= winbox-build-go
IMG_NSIS ?= winbox-build-nsis


.PHONY: all build-image installer clean

all:
	echo OK

update-winbox:
	wget -O WinBox_Windows.zip "https://download.mikrotik.com/routeros/winbox/$$(head -1 vars/current)/WinBox_Windows.zip"
	unzip WinBox_Windows.zip


image-c:
	docker build -f Dockerfile.c -t $(IMG_C) .

build-c: image-c
	docker run --rm \
		-v "$$(pwd)/src:/build" \
		$(IMG_C) \
		x86_64-w64-mingw32-gcc -O2 -mconsole -s \
		-o /build/connect-to-mt-64-c.exe \
		/build/connect-to-mt.c -lshlwapi

image-go:
	docker build -f Dockerfile.go -t $(IMG_GO) .

# Compile Go binary using Docker
build-go: image-go
	docker run --rm \
		-v "$$(pwd)/src:/build" \
		$(IMG_GO) \
		sh -c "cd /build && sh build-go.sh"

# Build NSIS Docker image
image-nsis:
	docker build -f Dockerfile.nsis -t $(IMG_NSIS) .

# Run NSIS packaging
nsis: image-nsis
	mkdir -p $(OUTPUT_DIR)
	docker run --rm \
		-v "$$(pwd):/build" \
		-w /build/src \
		$(IMG_NSIS) \
		installer.nsi

build-installer: nsis

clean:
	rm -rf $(OUTPUT_DIR) src/connect-to-mt-64.exe

