
function Invoke-WingetQuery {
    <#
    .SYNOPSIS
        Invokes a winget query.
    .DESCRIPTION
        A wrapper to run winget queries. The encoding is set to utf8 beforehand to avoid errors.
    .INPUTS
        Query: the winget command to be run.
    .OUTPUTS
        The output from winget.
    .EXAMPLE
        Invoke-WingetQuery -Query 'winget list'.
    .EXAMPLE
        Invoke-WingetQuery -Query 'winget find powershell'.
    .NOTES
        Winget may return text that contains characters that need a utf8 encoding to be displayed
        correctly. This wrapper is used to make sure the correct encoding is used.
    #>
    param(
        [ValidateScript(
            { $_ -match '^winget(\s|$).*'}
        )]
        [string] $Query
    )

    $consoleEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

    $wingetOutput = Invoke-Expression $Query
    
    [Console]::OutputEncoding = $consoleEncoding

    return $wingetOutput
}
