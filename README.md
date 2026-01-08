# Dream Droid Audio Docker

Multi-service audio processing Docker container that combines three JACK audio clients for speech recognition, noise reduction, and audio playback.

## Overview

This Docker container integrates three JACK client programs that work together to provide comprehensive audio processing:

1. **AIUI ASR** (`aiui/asrctl`) - Speech recognition service with TCP control interface
2. **VTN ZNOISE** (`vtn/znoise`) - Noise reduction and echo cancellation
3. **PLAYCTL** (`playctl/playctl`) - HTTP-controlled WAV playback service

## Architecture

### JACK Audio Routing

The system uses JACK audio server for low-latency audio routing between components:

#### AIUI + VTN Routing
```
system:capture_1 -> vtn:input_1
system:capture_2 -> vtn:input_2
vtn:output -> aiui:input
```

#### PLAYCTL Routing
```
playctl:output_left -> system:playback_1
playctl:output_right -> system:playback_2
```

#### PLAYCTL + VTN Routing
```
playctl:output_left -> vtn:reference_1
playctl:output_right -> vtn:reference_2
```

### Service Architecture

- **Host System**: JACK server runs on the host system
- **Container**: Only JACK clients run inside the container
- **Communication**: Uses shared memory (`/dev/shm`) and host IPC for JACK communication

## Prerequisites

### Host System Requirements


1. **System Packages** (on host):
```bash
   sudo apt install jackd2 jack-tools
```

2. **JACK Audio Server** must be running on the host system:
```bash
   # Start JACK server (example)
   jackd -d alsa -d plughw:0,0 -r 16000 -p 640 -n 2 &
```

3. **Docker** and **Docker Compose** installed

## Quick Start

### 1. Build the Container

```bash
docker-compose build
```

### 2. Start Services

```bash
docker-compose up -d
```

The container will automatically:
- Connect to the host JACK server
- Start all three services
- Configure JACK audio routing
- Keep services running

### 3. Check Status

```bash
# View logs
docker-compose logs -f

# Check service status inside container
docker exec dream-droid-jack-client /home/jackuser/app/run.sh status
```

### 4. Stop Services

```bash
docker-compose down
```

## Manual Service Management

You can manually control services inside the container:

```bash
# Enter container
docker exec -it dream-droid-jack-client bash

# Control all services
./run.sh start    # Start all services
./run.sh stop     # Stop all services
./run.sh restart  # Restart all services
./run.sh status   # Show service status
```

## Configuration

### Environment Variables

Configure in [`docker-compose.yml`](docker-compose.yml):

- `JACK_DEFAULT_SERVER`: JACK server name (default: `default`)
- `RUST_LOG`: Logging level for Rust applications (`debug`, `info`, `warn`, `error`)
- `AIUI_SN`: Serial number for AIUI service (modify in [`app/run.sh`](app/run.sh))
- `VTN_SN`: Serial number for VTN service (modify in [`app/run.sh`](app/run.sh))

### Service Directories

Each service runs in its own directory:

- **AIUI**: `/home/jackuser/app/aiui/`
- **VTN**: `/home/jackuser/app/vtn/`
- **PLAYCTL**: `/home/jackuser/app/playctl/`

Log files are written to the app root directory:
- `aiui.log`
- `vtn.log`
- `playctl.log`

## Troubleshooting

### JACK Server Not Available

**Problem**: Container logs show "JACK server not available"

**Solution**:
1. Verify JACK server is running on host:
   ```bash
   jack_lsp  # Should list JACK ports
   ```
2. Check shared memory access:
   ```bash
   ls -la /dev/shm
   ```
3. Ensure host networking is enabled in `docker-compose.yml`

### Services Not Starting

**Problem**: Services fail to start

**Solution**:
1. Check binary files exist:
   ```bash
   docker exec docker exec dream-droid-jack-client /home/jackuser/app/run.sh status ls -la /home/jackuser/app/*/
   ```
2. Check binary permissions:
   ```bash
   docker exec docker exec dream-droid-jack-client /home/jackuser/app/run.sh status stat /home/jackuser/app/aiui/asrctl
   ```
3. View service logs:
   ```bash
   docker exec docker exec dream-droid-jack-client /home/jackuser/app/run.sh status cat /home/jackuser/app/aiui.log
   docker exec docker exec dream-droid-jack-client /home/jackuser/app/run.sh status cat /home/jackuser/app/vtn.log
   docker exec docker exec dream-droid-jack-client /home/jackuser/app/run.sh status cat /home/jackuser/app/playctl.log
   ```

### JACK Port Connection Issues

**Problem**: JACK ports not connecting properly

**Solution**:
1. List available JACK ports:
   ```bash
   docker exec docker exec dream-droid-jack-client /home/jackuser/app/run.sh status jack_lsp
   ```
2. Check current connections:
   ```bash
   docker exec docker exec dream-droid-jack-client /home/jackuser/app/run.sh status jack_lsp -c
   ```
3. Manually reconnect if needed:
   ```bash
   docker exec docker exec dream-droid-jack-client /home/jackuser/app/run.sh status /home/jackuser/app/run.sh restart
   ```

### View JACK Connections

```bash
# Inside container or on host (if JACK is shared)
jack_lsp -c

# Show only specific service connections
jack_lsp -c | grep -A 5 "vtn:"
jack_lsp -c | grep -A 5 "aiui:"
jack_lsp -c | grep -A 5 "playctl:"
```

## Development

### Project Structure

```
.
├── Dockerfile              # Container image definition
├── docker-compose.yml      # Service orchestration
├── README.md              # This file
├── app/
│   ├── run.sh             # Main startup script (NEW)
│   ├── aiui/              # AIUI ASR service
│   │   ├── asrctl         # ASR binary
│   │   └── talk           # ASR tool
│   ├── vtn/               # VTN noise reduction service
│   │   ├── znoise         # VTN binary
│   │   ├── res/           # Resources (models, configs)
│   │   └── bin/output/    # Configuration files
│   └── playctl/           # PLAYCTL playback service
│       ├── playctl        # Playback binary
│       └── scripts/       # Helper scripts
└── lib/
    └── libvtn.so          # VTN shared library
```

### Adding New Services

To add a new JACK client service:

1. Add service directory under `app/`
2. Add start/stop functions in [`app/run.sh`](app/run.sh)
3. Add routing configuration in `connect_*_routing()` functions
4. Update this README with new service documentation

## Service APIs

### AIUI ASR Service

- **Protocol**: TCP
- **Purpose**: Voice recognition control
- **Commands**: Start/stop ASR processing

### VTN ZNOISE Service

- **Purpose**: Audio noise reduction and echo cancellation
- **Input**: System audio capture (2 channels)
- **Output**: Cleaned audio to ASR

### PLAYCTL Service

- **Protocol**: HTTP
- **Purpose**: WAV file playback control
- **Default Port**: 8080
- **Endpoints**: See service documentation


## jackd

共享内存目录位于 /dev/shm


## dep

### 建立音频文件存储目录
```bash
sudo mkdir -p /opt/voice-stack/assets/audio
sudo chown 1000:1000 /opt/voice-stack/assets/audio
sudo chmod 755 /opt/voice-stack/assets/audio

```