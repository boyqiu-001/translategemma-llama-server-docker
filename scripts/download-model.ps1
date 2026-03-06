param(
    [string]$ModelRoot = "./models/translategemma-12b-it-MP-GGUF",
    [string]$Repo = "steampunque/translategemma-12b-it-MP-GGUF",
    [string]$QuantFile = "translategemma-12b-it.Q4_K_H.gguf"
)

if (-not (Get-Command hf -ErrorAction SilentlyContinue)) {
    Write-Error "huggingface-cli (hf) is required. Install it first: pip install huggingface_hub[cli]"
    exit 1
}

New-Item -ItemType Directory -Path $ModelRoot -Force | Out-Null

Write-Host "Downloading $QuantFile and mmproj from $Repo ..."
hf download $Repo `
    $QuantFile `
    translategemma-12b-it.mmproj.gguf `
    --local-dir $ModelRoot

Write-Host "Done. Files saved in: $ModelRoot"
