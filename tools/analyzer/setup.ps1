# Installs the instrument analyzer (Demucs + Basic Pitch) in its own Python
# environment at %LOCALAPPDATA%\afinado\analyzer, where the app looks for it.
# Needs Python 3 on the PATH (only to bootstrap uv). About 1.5 GB.
#
#   powershell -ExecutionPolicy Bypass -File tools\analyzer\setup.ps1

$ErrorActionPreference = 'Stop'
$venv = Join-Path $env:LOCALAPPDATA 'afinado\analyzer'
$requirements = Join-Path $PSScriptRoot 'requirements.txt'

python -m pip install --user --quiet uv
python -m uv venv --python 3.11 $venv
$py = Join-Path $venv 'Scripts\python.exe'
python -m uv pip install --python $py -r $requirements
# Basic Pitch pulls TensorFlow on Windows, which clashes with numpy 2; the
# ONNX model is used instead.
python -m uv pip uninstall --python $py tensorflow tensorflow-intel tensorflow-estimator tensorflow-io-gcs-filesystem keras

# Download the separation model now rather than on the first song.
& $py -c "from demucs.pretrained import get_model; get_model('htdemucs_6s')"
Write-Host "Analisador instalado em $venv"
