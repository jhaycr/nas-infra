# Build the image
```bash
docker compose build
```

# Run commands

## Syntax
```bash
docker compose run --rm igir [command] [options]
```

## Examples

```bash
docker compose run --rm igir --version
docker compose run --rm igir copy --dat "*.dat" --input ROMs/ --output Cleaned/
docker compose run --rm igir validate --dat "No-Intro*.dat" --input ROMs/
docker compose run --rm igir report --input ROMs/
```

```bash
docker compose run --rm igir copy \
  --dat "*.dat" \
  --input New-ROMs/ \
  --input ROMs/ \
  --output ROMs/ \
  --clean
```

```bash
docker compose run --rm \
  -v "$(pwd)/dats:/data/dats:ro" \
  -v "$(pwd)/roms-unverified:/data/roms-unverified:ro" \
  -v "$(pwd)/roms-verified:/data/roms-verified" \
  igir \
  move extract report test \
  -d dats/ \
  -i "roms-unverified/" \
  -o "roms-verified/{romm}/" \
  --input-checksum-quick false \
  --input-checksum-min CRC32 \
  --input-checksum-max SHA256 \
  --only-retail
```

# Access shell

## Get interactive access

```bash
docker compose run --rm igir-shell
```

```bash
igir --version
igir copy --dat "*.dat" --input ROMs/ --output Cleaned/

cd /data
ls -l
```