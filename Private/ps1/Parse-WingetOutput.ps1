$wingetErrorstrings = Get-Content '.\winget-errorstrings.txt'

function Invoke-WingetQuery {
    param(
        [ValidateScript(
            { $_ -match '^winget\s.*'}
        )]
        [string] $Query
    )

    $previousConsoleEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
    $wingetOutput = Invoke-Expression $Query
    [Console]::OutputEncoding = $previousConsoleEncoding

    return $wingetOutput
}

function Parse-WingetOutput {
    param(
        #[ValidateNotNullOrEmpty()]
        [ValidateScript(
            { -not ($_ | Select-String $wingetErrorstrings) }
        )]
        [string[]] $WingetData
    )

    # $previousConsoleEncoding = [Console]::OutputEncoding
    # [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

    # The fist few lines of the winget output may contain gibberish.
    # The real data consists of a line of column headers, followed by a line of dashes '-' that separates
    # the headers from the data. The rest of the lines contain the package data.
    # The fist step is to identify the position of the separator line and get the line with names of the columns.
    $columnHeaderSeparator = $WingetData | Select-String -Pattern '^\-+$'
    if ($null -eq $columnHeaderSeparator) {
        Write-Error "Column header separator not found. Data is not in the right format."
        return $null
    }

    $columnHeaderLine = $wingetData | Select-Object -Index ($columnHeaderSeparator.LineNumber - 2)
    # Split the header line. Keep trailing whitespaces to be able to calculate the width of the columns.
    $columnHeaders = $columnHeaderLine -split '(?<=\s)(?=\S)'
    $columnCount = ($columnHeaders | Measure-Object).Count
    if ($columnCount -lt 2) {
        Write-Error "Could not separate column headers."
        return $null
    }

    # Some characters are printed two cells wide. This is taken into account by winget by adjusting the line lengths.
    # Those characters only seem to appear in the first column, wich consists of the package names.
    # To parse the lines into chunks, indices have to be reduced by the amount of those characters.
    # The following regex matches chinese, japanese and korean characters:
    # https://stackoverflow.com/questions/43418812/check-whether-a-string-contains-japanese-chinese-characters
    $wideCharRegex = '[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\uff66-\uff9f\u3131-\uD79D]'

    $result = foreach($dataLine in ($WingetData | Select-Object -Skip $columnHeaderSeparator.LineNumber)) {
        
        $data = [ordered]@{}

        # Count the amount of wide characters in the string
        $wideCharCount = ($dataLine | Select-String -AllMatches $wideCharRegex).Matches.Count

        # Treat the first column separately, because its length may be affected by the amount of wide characters.
        # For every other line the start of the text is affected.
        $firstColumnHeader = $columnHeaders | Select-Object -First 1
        $columnName = $firstColumnHeader.Trim()
        $columnText = $dataLine.Substring(0, $firstColumnHeader.Length - $wideCharCount).Trim()
        $data.Add($columnName, $columnText)

        foreach($columnHeader in $($columnHeaders | Select-Object -SkipIndex 0, ($columnCount - 1))) {
            $columnName = $columnHeader.Trim()
            $columnText = $dataLine.Substring($columnHeaderLine.IndexOf($columnHeader) - $wideCharCount, $columnHeader.Length).Trim()
            $data.Add($columnName, $columnText)
        }
        
        # Treat the last column separately, because the total length of the line may vary depending on the text for the source of the package.
        $lastColumnHeader = $columnHeaders | Select-Object -Last 1
        $columnName = $lastColumnHeader.Trim()
        $columnText = $dataLine.Substring($columnHeaderLine.IndexOf($lastColumnHeader) - $wideCharCount).Trim()
        $data.Add($columnName, $columnText)

        [pscustomobject]$data
    }

    return $result
}