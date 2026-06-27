param()
$api = "https://en.wiktionary.org/w/api.php"
$cats = @(
    "Category:en:Desserts",
    "Category:en:Cakes and pastries",
    "Category:en:Ice cream"
)
$names = @()
foreach ($cat in $cats) {
    $cmcont = $null
    do {
        $params = "action=query&list=categorymembers&cmtitle=$([System.Uri]::EscapeDataString($cat))&cmlimit=max&format=json"
        if ($cmcont) { $params += "&cmcontinue=$([System.Uri]::EscapeDataString($cmcont))" }
        $resp = Invoke-RestMethod -Uri "$api`?$params"
        foreach ($m in $resp.query.categorymembers) {
            if ($m.ns -eq 0) { $names += $m.title }
        }
        $cmcont = $resp.continue.cmcontinue
    } while ($cmcont)
}
if ($names.Count -eq 0) {
    Write-Error "No desserts found from Wiktionary API"
    exit 1
}
$codename = $names[(Get-Random -Maximum $names.Count)]
Write-Output "NovumOS $codename"
Set-Clipboard -Value $codename
