. "$PSScriptRoot\winget-errorstrings.ps1"
$wingetErrorstrings = Get-WingetErrorStrings

function Convert-WingetOutput {
    <#
    .SYNOPSIS
        Converts the output of winget to an object representation.
    .DESCRIPTION
        Winget commands like find or list return the list of packages as an array of strings wich represent 
        a table with the package information. This makes it hard to find a specific package automatically. 
        This function parses the strings and returns the package data as a list of pscustomobjects. 
        The output of winget may contain other information besides the table of package data. This extra 
        information is ignored.
    .INPUTS
        WingetData: the list of strings returned by a call to winget.
    .OUTPUTS
        Returns null, if the input does not contain a table with package data. Returns the contents of the 
        table as a list of pscustomobject otherwise.
    .EXAMPLE
        Convert-WingetOutput -WingetData $data
    .NOTES
        When storing the output of winget to a variable, the encoding has to be set to utf8. To make sure 
        of that use [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new() beforhand, or use the 
        helper function Invoke-WingetQuery.
    #>
    [CmdletBinding()]
    param (
        [ValidateScript(
            { -not ($_ | Select-String $wingetErrorstrings) }
        )]
        [string[]] $WingetData
    )

    # When storing the output of winget into a variable, progress data shown by winget is also stored. 
    # So the first few lines may contain some gibberish that has to be omitted.  
    # The data we are interested in consists of a line of column headers, followed by a line of dashes '-'
    # that separates the headers from the data. 
    # The real data consists of a line of column headers, followed by a line of dashes '-' that separates
    # the headers from the data. The rest of the lines contain the package data.
    #
    # Example data from 'winget find notepad++':
    # Name         Id                   Version Match          Source
    # ---------------------------------------------------------------
    # Notepad++    Notepad++.Notepad++  8.7.5                  winget
    # Notepad Next dail8859.NotepadNext 0.1     Tag: notepad++ winget

    # The lengths of the column names plus the trailing spaces to the next name can be used to identify 
    # the corresponding text inside the data lines.
    # Some characters are printed two cells wide inside consoles. This is taken into account by winget by 
    # adjusting the line lengths (i.e. reduce the trailing spaces to the next column by one per wide character).
    # Those characters only seem to appear in the first column, wich consists of the package names.
    # Some example for this with 'winget find python':
    #
    # Name                            Id                              Version         Match           Source
    # -------------------------------------------------------------------------------------------------------
    # [...]
    # C++ to Python Converter         9PBVQZ72QDQN                    Unknown                         msstore
    # 计算机二级 Python 考试题库      9PBKTNDS9VSH                    Unknown                         msstore
    # Anaconda3                       Anaconda.Anaconda3              2024.10-1       Command: python winget
    # [...]

    # To parse those lines into chunks, indices have to be reduced by the amount of those characters.
    # The following regex matches chinese, japanese and korean characters. It was taken from
    # https://stackoverflow.com/questions/43418812/check-whether-a-string-contains-japanese-chinese-characters
    $wideCharRegex = '[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\uff66-\uff9f\u3131-\uD79D]'

    # Identify the separator between the column headers and the data.
    $columnHeaderSeparator = $WingetData | Select-String -Pattern '^\-+$'
    if ($null -eq $columnHeaderSeparator) {
        Write-Error "Column header separator not found. Data is not in the right format."
        return $null
    }

    # Check the lengths of the strings in the table

    $columnHeaderLine = $wingetData | Select-Object -Index ($columnHeaderSeparator.LineNumber - 2)
    # Split the header line. Keep trailing whitespaces to be able to calculate the width of the columns.
    $columnHeaders = $columnHeaderLine -split '(?<=\s)(?=\S)'
    $columnCount = ($columnHeaders | Measure-Object).Count
    if ($columnCount -lt 2) {
        Write-Error "Could not separate column headers."
        return $null
    }


    $result = foreach ($dataLine in ($WingetData | Select-Object -Skip $columnHeaderSeparator.LineNumber)) {
        
        $data = [ordered]@{}

        # Count the amount of wide characters in the string
        $wideCharCount = ($dataLine | Select-String -AllMatches $wideCharRegex).Matches.Count

        # Treat the first column separately, because its length may be affected by the amount of wide characters.
        # For every other line the start of the text is affected.
        $firstColumnHeader = $columnHeaders | Select-Object -First 1
        $columnName = $firstColumnHeader.Trim()
        $columnText = $dataLine.Substring(0, $firstColumnHeader.Length - $wideCharCount).Trim()
        $data.Add($columnName, $columnText)

        foreach ($columnHeader in $($columnHeaders | Select-Object -SkipIndex 0, ($columnCount - 1))) {
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

    $result
}