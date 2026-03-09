param(
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [string]$ImagePath,
    [string]$ImageUrl,
    [string]$SourceLangCode = "en",
    [string]$TargetLangCode = "zh",
    [int]$MaxTokens = 500,
    [double]$Temperature = 0.2,
    [string]$Model,
    [switch]$RawResponse
)

function Get-ImageBytes {
    param(
        [string]$Path,
        [string]$Url
    )

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        $resolvedPath = (Resolve-Path $Path).Path
        return [System.IO.File]::ReadAllBytes($resolvedPath)
    }

    if ([string]::IsNullOrWhiteSpace($Url)) {
        throw "Please provide -ImagePath or -ImageUrl."
    }

    $tempFile = [System.IO.Path]::GetTempFileName()
    try {
        Invoke-WebRequest -Uri $Url -OutFile $tempFile -TimeoutSec 300 | Out-Null
        return [System.IO.File]::ReadAllBytes($tempFile)
    } finally {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }
}

function Get-LanguageName {
    param([string]$Code)

    $names = @{
        ar = "Arabic"
        az = "Azerbaijani"
        bg = "Bulgarian"
        bn = "Bengali"
        ca = "Catalan"
        cs = "Czech"
        da = "Danish"
        de = "German"
        el = "Greek"
        en = "English"
        eo = "Esperanto"
        es = "Spanish"
        et = "Estonian"
        eu = "Basque"
        fa = "Persian"
        fi = "Finnish"
        fr = "French"
        ga = "Irish"
        gl = "Galician"
        he = "Hebrew"
        hi = "Hindi"
        hu = "Hungarian"
        id = "Indonesian"
        it = "Italian"
        ja = "Japanese"
        ko = "Korean"
        lt = "Lithuanian"
        lv = "Latvian"
        ms = "Malay"
        nb = "Norwegian Bokmal"
        nl = "Dutch"
        pl = "Polish"
        pt = "Portuguese"
        ro = "Romanian"
        ru = "Russian"
        sk = "Slovak"
        sl = "Slovenian"
        sq = "Albanian"
        sv = "Swedish"
        th = "Thai"
        tl = "Tagalog"
        tr = "Turkish"
        uk = "Ukrainian"
        ur = "Urdu"
        zh = "Chinese"
        'zh-Hant' = "Traditional Chinese"
        zt = "Traditional Chinese"
    }

    if ($names.ContainsKey($Code)) {
        return $names[$Code]
    }

    return $Code
}

function New-ImagePrompt {
    param(
        [string]$SourceLangCode,
        [string]$TargetLangCode
    )

    $sourceName = Get-LanguageName -Code $SourceLangCode
    $targetName = Get-LanguageName -Code $TargetLangCode

    return @"
<start_of_turn>user
You are a professional $sourceName ($SourceLangCode) to $targetName ($TargetLangCode) translator. Your goal is to accurately convey the meaning and nuances of the original $sourceName text while adhering to $targetName grammar, vocabulary, and cultural sensitivities.
Please translate the $sourceName text in the provided image into $targetName. Produce only the $targetName translation, without any additional explanations, alternatives or commentary. Focus only on the text, do not output where the text is located, surrounding objects or any other explanation about the picture. Ignore symbols, pictogram, and arrows!


<__media__><end_of_turn>
<start_of_turn>model
"@
}

if ([string]::IsNullOrWhiteSpace($ImagePath) -and [string]::IsNullOrWhiteSpace($ImageUrl)) {
    Write-Error "Please provide -ImagePath or -ImageUrl."
    exit 1
}

if (-not [string]::IsNullOrWhiteSpace($ImagePath) -and -not (Test-Path $ImagePath)) {
    Write-Error "Image file not found: $ImagePath"
    exit 1
}

$imageBytes = Get-ImageBytes -Path $ImagePath -Url $ImageUrl
$imageBase64 = [System.Convert]::ToBase64String($imageBytes)
$prompt = New-ImagePrompt -SourceLangCode $SourceLangCode -TargetLangCode $TargetLangCode
$baseUrlTrimmed = $BaseUrl.TrimEnd('/')

$payload = [ordered]@{
    prompt = [ordered]@{
        prompt_string = $prompt
        multimodal_data = @($imageBase64)
    }
    n_predict = $MaxTokens
    temperature = $Temperature
    stream = $false
}

if (-not [string]::IsNullOrWhiteSpace($Model)) {
    $payload.model = $Model
}

$jsonBody = $payload | ConvertTo-Json -Depth 10

Write-Host "POST $baseUrlTrimmed/completion"
if (-not [string]::IsNullOrWhiteSpace($ImagePath)) {
    Write-Host "ImagePath: $((Resolve-Path $ImagePath).Path)"
} else {
    Write-Host "ImageUrl: $ImageUrl"
}
Write-Host "Translate: $SourceLangCode -> $TargetLangCode"
Write-Host "PayloadMode: completion-multimodal"

try {
    $response = Invoke-RestMethod `
        -Method Post `
        -Uri "$baseUrlTrimmed/completion" `
        -ContentType "application/json; charset=utf-8" `
        -Body $jsonBody `
        -TimeoutSec 300
} catch {
    Write-Error "Request failed: $($_.Exception.Message)"

    if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
        Write-Host $_.ErrorDetails.Message
    }

    exit 1
}

if ($RawResponse) {
    $response | ConvertTo-Json -Depth 10
    exit 0
}

$translation = $response.content

if ([string]::IsNullOrWhiteSpace($translation)) {
    Write-Warning "Response does not contain completion content."
    $response | ConvertTo-Json -Depth 10
    exit 0
}

Write-Host ""
Write-Host "Translation Result:" -ForegroundColor Green
Write-Output $translation.Trim()
