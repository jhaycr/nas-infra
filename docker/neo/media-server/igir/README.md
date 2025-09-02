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
docker run --rm \
  -v "$(pwd)/dats:/data/dats:ro" \
  -v "$(pwd)/roms-unverified:/data/roms-unverified" \
  -v "$(pwd)/roms-verified:/data/roms-verified" \
  -w /data \
  igir-app \
  move extract report test \
  -d dats \
  -i "roms-unverified/" \
  -o "roms-verified/{romm}/" \
  --dir-dat-name
  -v
```

# Access shell

## Get interactive access

```bash
docker compose run --rm igir-shell
```

```bash
igir move zip report test \
  --dat dats \
  --input "roms-unverified/" \
  --output "roms-verified/{romm}/" \
  --temp-dir "/tmp/igir" \
  --report-output "/tmp/igir/report %dddd, %MMMM %Do %YYYY, %h:%mm:%ss %a.csv" \
  --dir-dat-name \
  -v

cd /data
ls -l
```