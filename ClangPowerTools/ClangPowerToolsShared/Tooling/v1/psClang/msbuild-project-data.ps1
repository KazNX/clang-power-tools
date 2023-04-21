#-------------------------------------------------------------------------------------------------
# PlatformToolset constants

Set-Variable -name kDefinesUnicode   -value @('"-DUNICODE"'
                                             ,'"-D_UNICODE"'
                                             ) `
                                     -option Constant

Set-Variable -name kDefinesClangXpTargeting `
             -value @('"-D_USING_V110_SDK71_"') `
             -option Constant

Set-Variable -name kIncludePathsXPTargetingSDK  `
             -value "${Env:ProgramFiles(x86)}\Microsoft SDKs\Windows\v7.1A\Include"  `
             -option Constant

Set-Variable -name kVStudioDefaultPlatformToolset -Value "v141" -option Constant

Set-Variable -name kClangFlag32BitPlatform        -value "-m32" -option Constant

# ------------------------------------------------------------------------------------------------
# Default platform sdks and standard

Set-Variable -name kVSDefaultWinSDK            -value '8.1'             -option Constant
Set-Variable -name kVSDefaultWinSDK_XP         -value '7.0'             -option Constant
Set-Variable -name kDefaultCppStd              -value "stdcpp14"        -option Constant

# ------------------------------------------------------------------------------------------------
Set-Variable -name kCProjectCompile         -value "CompileAsC" -option Constant

Function Should-CompileProject([Parameter(Mandatory = $true)][string] $vcxprojPath)
{
    if ($aVcxprojToCompile -eq $null)
    {
        return $true
    }

    foreach ($projMatch in $aVcxprojToCompile)
    {
        if (IsFileMatchingName -filePath $vcxprojPath -matchName $projMatch)
        {
            return $true
        }
    }

    return $false
}

Function Should-IgnoreProject([Parameter(Mandatory = $true)][string] $vcxprojPath)
{
    if ($aVcxprojToIgnore -eq $null)
    {
        return $false
    }

    foreach ($projIgnoreMatch in $aVcxprojToIgnore)
    {
        if (IsFileMatchingName -filePath $vcxprojPath -matchName $projIgnoreMatch)
        {
            return $true
        }
    }

    return $false
}

Function Should-IgnoreFile([Parameter(Mandatory = $true)][string] $file)
{
    if ($aCppToIgnore -eq $null)
    {
        return $false
    }

    foreach ($projIgnoreMatch in $aCppToIgnore)
    {
        if (IsFileMatchingName -filePath $file -matchName $projIgnoreMatch)
        {
            return $true
        }
    }

    foreach ($projIgnoreMatch in $global:cptIgnoredFilesPool)
    {
        if (IsFileMatchingName -filePath $file -matchName $projIgnoreMatch)
        {
            return $true
        }
    }

    return $false
}

Function Get-ProjectFilesToCompile()
{
    $projectCompileItems = @(Get-Project-ItemList "ClCompile")
    if (!$projectCompileItems)
    {
        Write-Verbose "Project does not have any items to compile"
        return @()
    }

    $files = @()
    foreach ($item in $projectCompileItems)
    {
        [System.Collections.Hashtable] $itemProps = $item[1];

        if ($itemProps -and $itemProps.ContainsKey('ExcludedFromBuild'))
        {
            if ($itemProps['ExcludedFromBuild'] -ieq 'true')
            {
                Write-Verbose "Skipping $($item[0]) because it is excluded from build"
                continue
            }
        }

        [string[]] $matchedFiles = @(Canonize-Path -base $ProjectDir -child $item[0] -ignoreErrors)
        if ($matchedFiles.Count -gt 0)
        {
            foreach ($file in $matchedFiles)
            {
                $files += New-Object PsObject -Prop @{ "File"       = $file
                                                     ; "Properties" = $itemProps
                                                     }
            }
        }
    }

    return $files
}

Function Get-ProjectHeaders()
{
    $projectCompileItems = @(Get-Project-ItemList "ClInclude")

    [string[]] $headerPaths = @()

    foreach ($item in $projectCompileItems)
    {
        [string[]] $paths = @(Canonize-Path -base $ProjectDir -child $item[0] -ignoreErrors)
        if ($paths.Count -gt 0)
        {
            $headerPaths += $paths
        }
    }
    return $headerPaths
}

Function Get-Project-SDKVer()
{
    if (! (VariableExists 'WindowsTargetPlatformVersion'))
    {
        return ""
    }

    if ([string]::IsNullOrEmpty($WindowsTargetPlatformVersion))
    {
        return ""
    }

    return $WindowsTargetPlatformVersion.Trim()
}

Function Get-Project-MultiThreaded-Define()
{
    Set-ProjectItemContext "ClCompile"
    [string] $runtimeLibrary = Get-ProjectItemProperty "RuntimeLibrary"

    # /MT or /MTd
    if (@("MultiThreaded", "MultiThreadedDebug") -contains $runtimeLibrary)
    {
        return @('"-D_MT"')
    }

    return @('"-D_MT"', '"-D_DLL"') # default value /MD
}

Function Is-Project-Unicode()
{
    if (VariableExists 'CharacterSet')
    {
        return $CharacterSet -ieq "Unicode"
    }
    return $false
}

Function Get-Project-CppStandard()
{
    if ((Is-NMakeProject))
    {
        # For an NMake project, lookin in the $AdditionalOptions for the project.
        if ((VariableExists "AdditionalOptions"))
        {
            foreach ($option in $AdditionalOptions)
            {
                [string] $cppStdOpt = "/std:c++"
                if ($option.StartsWith($cppStdOpt))
                {
                    # Enumlate the project setting for a non NMake project to let the remaining
                    # function logic to play out.
                    $cppStd = "stdcpp" + $option.Substring($cppStdOpt.Length)
                    break
                }
            }
        }
    }
    else
    {
        Set-ProjectItemContext "ClCompile"
        $cppStd = Get-ProjectItemProperty "LanguageStandard"
    }

    if (!$cppStd)
    {
        $cppStd = $kDefaultCppStd
    }

    $cppStdMap = @{ 'stdcpplatest' = 'c++20'
                  ; 'stdcpp14'     = 'c++14'
                  ; 'stdcpp17'     = 'c++17'
                  ; 'stdcpp20'     = 'c++20'
                  }
    if ($kLLVMVersion -ge 13)
    {
        $cppStdMap['stdcpplatest'] = 'c++2b'
    }

    [string] $cppStdClangValue = $cppStdMap[$cppStd]

    return $cppStdClangValue
}

Function Get-ClangCompileFlags([Parameter(Mandatory = $false)][bool] $isCpp = $true)
{
    [string[]] $flags = $aClangCompileFlags
    if ($isCpp -and !($flags -match "-std=.*"))
    {
        [string] $cppStandard = Get-Project-CppStandard

        $flags = @("-std=$cppStandard") + $flags
    }

    if ($Platform -ieq "x86" -or $Platform -ieq "Win32")
    {
        $flags += @($kClangFlag32BitPlatform)
    }

    return $flags
}

Function Get-ProjectPlatformToolset()
{
    if (VariableExists 'PlatformToolset')
    {
        return $PlatformToolset
    }
    else
    {
        return $kVStudioDefaultPlatformToolset
    }
}
function Get-LatestSDKVersion()
{
    [string] $parentDir = "${Env:ProgramFiles(x86)}\Windows Kits\10\Include\"
    if (!(Test-Path -LiteralPath $parentDir))
    {
        Write-Verbose "Windows 10 SDK parent directory could not be located"
        return ""
    }

    [System.IO.DirectoryInfo[]]$subdirs = @( get-childitem -path $parentDir      | `
                                             where { $_.Name.StartsWith("10.") } | `
                                             sort -Descending -Property Name )
    if ($subdirs.Count -eq 0)
    {
        Write-Verbose "[ERR] Could not detect latest Windows 10 SDK location"
        return ""
    }

    return $subdirs[0].Name
}

Function Get-ProjectIncludesFromIncludePathVar
{
    [string[]] $returnArray = @()
    if ( (VariableExists 'IncludePath') )
    {
        $returnArray += ($IncludePath -split ";")                                                         | `
                        Where-Object { ![string]::IsNullOrWhiteSpace($_) }                                | `
                        ForEach-Object { Canonize-Path -base $ProjectDir -child $_.Trim() -ignoreErrors } | `
                        Where-Object { ![string]::IsNullOrEmpty($_) }                                     | `
                        ForEach-Object { $_ -replace '\\$', '' }
    }
    return $returnArray
}

Function Get-ProjectIncludeDirectories()
{
    [string[]] $returnArray = @()

    [string] $vsPath = Get-VisualStudio-Path
    Write-Verbose "Visual Studio location: $vsPath"

    [string] $platformToolset = Get-ProjectPlatformToolset

    if (([int] $global:cptVisualStudioVersion) -lt 2017)
    {
        $returnArray += Get-VisualStudio-Includes -vsPath $vsPath
    }
    else
    {
        $mscVer = Get-MscVer -visualStudioPath $vsPath
        Write-Verbose "MSCVER: $mscVer"

        $returnArray += Get-VisualStudio-Includes -vsPath $vsPath -mscVer $mscVer
    }

    # Only add the Windows SDK includes for a non-makefile project.
    # NMake should add the SDK includes via the AdditionalIncludeDirectories
    if (!(Is-NMakeProject))
    {
        $sdkVer = Get-Project-SDKVer

        # We did not find a WinSDK version in the vcxproj. We use Visual Studio's defaults
        if ([string]::IsNullOrEmpty($sdkVer))
        {
            if ($platformToolset.EndsWith("xp"))
            {
                $sdkVer = $kVSDefaultWinSDK_XP
            }
            else
            {
                $sdkVer = $kVSDefaultWinSDK
            }
        }

        Write-Verbose "WinSDK version: $sdkVer"

        # ----------------------------------------------------------------------------------------------
        # Windows 10

        if ((![string]::IsNullOrEmpty($sdkVer)) -and ($sdkVer.StartsWith("10")))
        {
            if ($sdkVer -eq "10.0")
            {
                # Project uses the latest Win10 SDK. We have to detect its location.
                $sdkVer = Get-LatestSDKVersion
            }

            $returnArray += @("${Env:ProgramFiles(x86)}\Windows Kits\10\Include\$sdkVer\ucrt")

            if ($platformToolset.EndsWith("xp"))
            {
                $returnArray += @($kIncludePathsXPTargetingSDK)
            }
            else
            {
                $returnArray += @( "${Env:ProgramFiles(x86)}\Windows Kits\10\Include\$sdkVer\um"
                    , "${Env:ProgramFiles(x86)}\Windows Kits\10\Include\$sdkVer\shared"
                    , "${Env:ProgramFiles(x86)}\Windows Kits\10\Include\$sdkVer\winrt"
                    , "${Env:ProgramFiles(x86)}\Windows Kits\10\Include\$sdkVer\cppwinrt"
                )
            }
        }

        # ----------------------------------------------------------------------------------------------
        # Windows 8 / 8.1

        if ((![string]::IsNullOrEmpty($sdkVer)) -and ($sdkVer.StartsWith("8.")))
        {
            $returnArray += @("${Env:ProgramFiles(x86)}\Windows Kits\10\Include\10.0.10240.0\ucrt")

            if ($platformToolset.EndsWith("xp"))
            {
                $returnArray += @($kIncludePathsXPTargetingSDK)
            }
            else
            {
                $returnArray += @( "${Env:ProgramFiles(x86)}\Windows Kits\$sdkVer\Include\um"
                    , "${Env:ProgramFiles(x86)}\Windows Kits\$sdkVer\Include\shared"
                    , "${Env:ProgramFiles(x86)}\Windows Kits\$sdkVer\Include\winrt"
                )
            }
        }

        # ----------------------------------------------------------------------------------------------
        # Windows 7

        if ((![string]::IsNullOrEmpty($sdkVer)) -and ($sdkVer.StartsWith("7.0")))
        {
            $returnArray += @("$vsPath\VC\Auxiliary\VS\include")

            if ($platformToolset.EndsWith("xp"))
            {
                $returnArray += @( "${Env:ProgramFiles(x86)}\Windows Kits\10\Include\10.0.10240.0\ucrt"
                    , $kIncludePathsXPTargetingSDK
                )
            }
            else
            {
                $returnArray += @( "${Env:ProgramFiles(x86)}\Windows Kits\10\Include\7.0\ucrt")
            }
        }
    }

    if ($env:CPT_LOAD_ALL -eq '1')
    {
        return @(Get-ProjectIncludesFromIncludePathVar)
    }
    else
    {
        $returnArray += @(Get-ProjectIncludesFromIncludePathVar)
    }

    return ( $returnArray | ForEach-Object { Remove-PathTrailingSlash -path $_ } )
}

<#
.DESCRIPTION
  Retrieve array of preprocessor definitions for a given project, in Clang format (-DNAME )
#>
Function Get-ProjectPreprocessorDefines()
{
    [string[]] $defines = @()

    if (Is-Project-Unicode)
    {
        $defines += $kDefinesUnicode
    }

    $defines += @(Get-Project-MultiThreaded-Define)

    if ( (VariableExists 'UseOfMfc') -and $UseOfMfc -ieq "Dynamic")
    {
        $defines += @('"-D_AFXDLL"')
    }

    [string] $platformToolset = Get-ProjectPlatformToolset
    if ($platformToolset.EndsWith("xp"))
    {
        $defines += $kDefinesClangXpTargeting
    }

    Set-ProjectItemContext "ClCompile"
    $preprocDefNodes = Get-ProjectItemProperty "PreprocessorDefinitions"
    if (!$preprocDefNodes)
    {
        return $defines
    }

    [string[]] $tokens = @($preprocDefNodes -split ";")

    # make sure we add the required prefix and escape double quotes
    $defines += @( $tokens | `
                   ForEach-Object { $_.Trim() } | `
                   Where-Object { $_ } | `
                   ForEach-Object { '"' + $(($kClangDefinePrefix + $_) -replace '"', '\"') + '"' } )

    return $defines
}


Function Get-ProjCanonizedPaths([Parameter(Mandatory = $true)][string] $rawPaths)
{
    [string[]] $tokens = @($rawPaths -split ";")

    foreach ($token in $tokens)
    {
        if ([string]::IsNullOrWhiteSpace($token))
        {
            continue
        }

        [string] $includePath = Canonize-Path -base $ProjectDir -child $token.Trim() -ignoreErrors
        if (![string]::IsNullOrEmpty($includePath))
        {
            $includePath -replace '\\$', ''
        }
    }
}

Function Get-ProjectExternalIncludePaths()
{
    if (!(VariableExistsAndNotEmpty -name "ExternalIncludePath"))
    {
       return @()
    }
    return Get-ProjCanonizedPaths -rawPaths $ExternalIncludePath
}

Function Get-ProjectAdditionalIncludes()
{
    Set-ProjectItemContext "ClCompile"
    $data = Get-ProjectItemProperty "AdditionalIncludeDirectories"
    if (!(VariableExistsAndNotEmpty -name "data"))
    {
        return @()
    }
    return Get-ProjCanonizedPaths -rawPaths $data
}

Function Get-ProjectForceIncludes()
{
    Set-ProjectItemContext "ClCompile"
    $forceIncludes = Get-ProjectItemProperty "ForcedIncludeFiles"
    if ($forceIncludes)
    {
        return @($forceIncludes -split ";" | Where-Object { ![string]::IsNullOrWhiteSpace($_) })
    }

    return $null
}

Function Get-FileForceIncludes([Parameter(Mandatory=$true)] [string] $fileFullName)
{
    try
    {
        [string] $forceIncludes = Get-ProjectFileSetting -fileFullName $fileFullName -propertyName "ForcedIncludeFiles"
        return ($forceIncludes -split ";")                                                       | `
               Where-Object { ![string]::IsNullOrWhiteSpace($_) }                                | `
               ForEach-Object { Canonize-Path -base $ProjectDir -child $_.Trim() -ignoreErrors } | `
               Where-Object { ![string]::IsNullOrEmpty($_) }                                     | `
               ForEach-Object { $_ -replace '\\$', '' }
    }
    catch
    {
        return $null
    }
}


Function Get-FileAdditionalIncludes([Parameter(Mandatory=$true)] [string] $fileFullName)
{
    try
    {
        [string] $forceIncludes = Get-ProjectFileSetting -fileFullName $fileFullName -propertyName "AdditionalIncludeDirectories"
        return ($forceIncludes -split ";")                                                       | `
               Where-Object { ![string]::IsNullOrWhiteSpace($_) }                                | `
               # Canonizing the path will remove items which don't exist. This is good, we can end
               # up losing an include path which is created later when the project settings are
               # cached.
               ForEach-Object { Canonize-Path -base $ProjectDir -child $_.Trim() -ignoreErrors } | `
               Where-Object { ![string]::IsNullOrEmpty($_) }                                     | `
               ForEach-Object { $_ -replace '\\$', '' }
    }
    catch
    {
        return $null
    }
}


<#
.DESCRIPTION
  Retrieve directory in which stdafx.h resides
#>
Function Get-ProjectStdafxDir( [Parameter(Mandatory = $true)]  [string]   $pchHeaderName
    , [Parameter(Mandatory = $false)] [string[]] $includeDirectories
    , [Parameter(Mandatory = $false)] [string[]] $additionalIncludeDirectories
)
{
    [string] $stdafxPath = ""

    [string[]] $projectHeaders = @(Get-ProjectHeaders)
    if ($projectHeaders.Count -gt 0)
    {
        # we need to use only backslashes so that we can match against file header paths
        $pchHeaderName = $pchHeaderName.Replace("/", "\")

        $stdafxPath = $projectHeaders | Where-Object { (Get-FileName -path $_) -eq $pchHeaderName }
    }

    if ([string]::IsNullOrEmpty($stdafxPath))
    {
        [string[]] $searchPool = @($ProjectDir);
        if ($null -ne $includeDirectories -and $includeDirectories.Count -gt 0)
        {
            $searchPool += $includeDirectories
        }
        if ($null -ne $additionalIncludeDirectories -and $additionalIncludeDirectories.Count -gt 0)
        {
            $searchPool += $additionalIncludeDirectories
        }

        foreach ($dir in $searchPool)
        {
            [string] $stdafxPathTest = Canonize-Path -base $dir -child $pchHeaderName -ignoreErrors
            if (![string]::IsNullOrEmpty($stdafxPathTest))
            {
                $stdafxPath = $stdafxPathTest
                break
            }
        }
    }

    if ([string]::IsNullOrEmpty($stdafxPath))
    {
        return ""
    }
    # Handle case where the PCH header project setting contains directory names from upper hierarchy.
    # E.g. <PrecompiledHeaderFile>$(ProjectName)\$(ProjectName)_headers.h</PrecompiledHeaderFile>
    # More details at https://github.com/Caphyon/clang-power-tools/issues/1227
    # Don't do this if the names exactly match.
    elseif ($stdafxPath.EndsWith($pchHeaderName) -and $stdafxPath -cne $pchHeaderName)
    {
        [string] $stdafxDir = $stdafxPath.Remove($stdafxPath.Length - $pchHeaderName.Length)
        return $stdafxDir
    }
    else
    {
        [string] $stdafxDir = Get-FileDirectory($stdafxPath)
        return $stdafxDir
    }
}

<#
.DESCRIPTION
Find the source file used to generate the given PCH header file.
#>
Function Find-PchSourceFile([Parameter(Mandatory)] [string] $pchHeaderName,
                            [Parameter(Mandatory)] [System.Collections.IEnumerable] $projectFiles,
                            [string] $pchFilePath = "")
{
    foreach ($projCpp in $projectFiles)
    {
        if ( (Get-ProjectFileSetting -fileFullName $projCpp -propertyName 'PrecompiledHeader') -ieq 'Create')
        {
            [string] $testPchHeader = Get-ProjectFileSetting -fileFullName $projCpp -propertyName 'PrecompiledHeaderFile'
            if ($testPchHeader -ceq $pchHeaderName)
            {
                return $projCpp
            }
        }
    }

    # Sadly we must guess the extension by trial and error.
    [string[]] $sourceExtensions = @(
        ".cpp",
        ".cxx",
        ".c++",
        ".c"
    )

    # Failed to locate by finding the source file which compiles the pchHeaderName.
    # Try locate on the file system instead. This is important for NMake projects like
    # Unreal Ungine projects.
    # First find the PCH file.
    [string] $pchHeaderFullPath = $pchHeaderName
    if ($pchFilePath)
    {
        $pchHeaderFullPath = $pchFilePath
    }

    if ([System.IO.Path]::Exists($pchHeaderFullPath))
    {
        foreach ($ext in $sourceExtensions)
        {
            [string] $pchSource = [System.IO.Path]::ChangeExtension($pchHeaderFullPath, $ext)
            if ([System.IO.Path]::Exists($pchSource))
            {
                return $pchSource
            }
        }
    }

    return ""
}

<#
.DESCRIPTION
Get the header file associated witha precompiled header soure file.

There are two ways to get this information.

1. Try read the PrecompiledHeaderFile property of the given cpp file.
2. Parse the cpp file and extract the first #include directive.

This checks the settings of each of the given $projectFiles, examines each items PrecompiledHeader
property and returns the file with PrecompiledHeader = Create, returning the associated cpp file.
#>
Function Get-PchCppIncludeHeader([Parameter(Mandatory = $true)][string] $pchCppFile)
{
    # 1. Try the PrecompiledHeaderFile property
    [string] $pchPath = Get-ProjectFileSetting -fileFullName $pchCppFile -propertyName 'PrecompiledHeaderFile' -defaultValue ""
    if (![string]::IsNullOrEmpty($pchPath))
    {
        return $pchPath
    }

    # 2. Fallback to parsing the first include in the cpp file.
    [string] $cppPath = Canonize-Path -base $ProjectDir -child $pchCppFile

    [string[]] $fileLines = @(Get-Content -LiteralPath $cppPath)
    foreach ($line in $fileLines)
    {
        $regexMatch = [regex]::match($line, '^\s*#include\s+"(\S+)"')
        if ($regexMatch.Success)
        {
            return $regexMatch.Groups[1].Value
        }
    }
    return ""
}

<#
.DESCRIPTION
Identify the cpp source file used to generate the .pch file.

This checks the settings of each of the given $projectFiles, examines each items PrecompiledHeader
property and returns the file with PrecompiledHeader = Create, returning the associated cpp file.
#>
Function Get-ProjectPrecompiledHeaderSource([Parameter(Mandatory = $true)] [System.Collections.IEnumerable] $projectFiles)
{
    foreach ($projCpp in $projectFiles)
    {
        if ( (Get-ProjectFileSetting -fileFullName $projCpp -propertyName 'PrecompiledHeader') -ieq 'Create')
        {
            return $projCpp
        }
    }
    return ""
}

<#
.DESCRIPTION
Identify the precompiled header file required to compile the specified $fileFullName in the current project.

For an MSBuild project, the we check the PrecompiledHeader property of $fileFullName ensuring it is
set to "Use" (rather than "Create" or not being used). The header itself is identified by the
PrecompiledHeaderFile property.

For an NMake project we check the AdditionalOptions property of $fileFullName and search for the
compiler option /Yu<pch.h> and extract <pch.h> as required.
#>
Function Get-FilePrecompiledHeader([Parameter(Mandatory = $true)] [string] $fileFullName)
{
    if ((Is-NMakeProject))
    {
        # For an NMake project (including Unreal projects) we check a file's "AdditionalOptions" for
        # a PCH include directive.
        [string] $additionalOptions = Get-ProjectFileSetting -fileFullName $fileFullName -propertyName "AdditionalOptions" -defaultValue ""
        $regexMatch = [regex]::Match($additionalOptions, '/Yu((".*")|([^ ]+))')
        if ($regexMatch.Success)
        {
            [string] $pchPath = $regexMatch.Groups[1].Value
            return $pchPath.Trim('"')
        }
    }

    if ( (Get-ProjectFileSetting -fileFullName $fileFullName -propertyName 'PrecompiledHeader' -defaultValue "") -ieq 'Use')
    {
        [string] $pchPath = Get-ProjectFileSetting -fileFullName $fileFullName -propertyName 'PrecompiledHeaderFile' -defaultValue ""
    }
    
    # FIXME(Kaz): arguably we could do something similar for non NMake projects.
    return ""
}

Function Is-NMakeProject()
{
    if ((VariableExists "Keyword") -and $Keyword -eq "MakeFileProj")
    {
        return $true
    }
    return $false
}

<#
.DESCRIPTION
Fix clang-tidy program arguments to work with an Urneal project, provided we have an Unreal project.

An Unreal project is detected by having $UnrealProject previously set (during project load).

For such a project we must modify the command line arguments as follows:

- If $pchFilePath is given:
    - Find the equivalent generating heading file in force includes and remove it.
- If $pchFilePath not given:
    - Change the order of the force includes. We expect Unreal PCH, then source file header, but having
    the PCH first prevents clang from compiling since it's not a valid clang PCH file. Swapping the
    order is a workaround as it's no longer treated as a PCH file.
- Add additional preprocessor directives to;
  - Work around a clang incompability in Unreal. This turns a built in pause instruction into a
    noop, which is ok for clang-tidy, but not for clang compilation.

We assume that Get-Project-CppStandard handles converting /std:c++xx to -std=c++xx.

This function should only be called for a clang-tidy run, not a clang compilation.

.PARAMETER preprocessorDefinitions
A reference to the array of preprocessor directives to compile with. This is modified to contain
additional macros which allow clang-tidy to compile but would be incorrect for clang. It also
erases the Unreal Engine meta parser macros.

.PARAMETER forceIncludes
The list of force includes for the current file. For an Unreal project, this is expected to have
two items: the PCH header to to include and the meta parser generated header, in that order. If we
leave the PCH header first, then clang-tidy will fail, identifying that that MSVC generated .h.pch
file is invalid for clang-tidy. We can work around this by switching the include order unless
$pchFilePath is also provided.

.PARAMETER pchFilePath
Optional file path to the header used to generate a clang precompiled header output (PCH) for the
PCH listed in $forceIncludes. When provided, we assume that a clang compatible PCH compilation has
been made of the first header listed in $forceIncludes. We remove this header from $forceIncludes
provided $forceIncludes.Value[0] exactly matches pchFilePath. clang-tidy must then be run with
"-include-pch" targetting the clang generated output for this PCH header. Note this is the path to
the original header. It is not the .hpp file used to generate the clang header, nor is it the
.clang.pch file.

.PARAMETER disableMacroWarning
When present, disable the macro redefinition warning. This is useful for suppressing PCH generation
errors for UE PCH files because we deliberately redefine __has_builtin to get UE to compile with
clang-tidy. It's a workaround.

.PARAMETER disableMetaMacros
Adds preprocessor directives which mask out the Unreal Engine meta parser macros. These can cause
issues with clang-tidy compilation.
#>
Function FixUnrealProjectArguments(
    [Parameter(Mandatory = $true)] [ref] $preprocessorDefinitions,
    [Parameter(Mandatory = $true)] [ref] $forceIncludes,
    [Parameter(Mandatory = $false)][string] $pchFilePath = "",
    [Parameter(Mandatory = $false)][switch] $disableMacroWarning,
    [Parameter(Mandatory = $false)][switch] $disableMetaMacros)
{
  if (!$UnrealProject) {
    # Not an unreal project. Nothing to do.
    return;
  }

  [bool] $pchIncludeFound = $false
  if (![string]::IsNullOrEmpty($pchFilePath))
  {
    # PCH path specified. Find the mathcing PCH in the $forceIncludes and remove it. It will be
    # the first item or it's not really a PCH.
    if ($forceIncludes.Value.Length -gt 1)
    {
      if ($forceIncludes.Value[0] -ceq $pchFilePath)
      {
        # Replace the array with the first item removed.
        $n = $forceIncludes.Value.Length - 1
        # Array slice: keep Length-1 items from the end
        $forceIncludes.Value = $forceIncludes.Value[-$n..-1]
        $pchIncludeFound = $true
      }
    }
  }

  if (!$pchIncludeFound)
  {
    if ($forceIncludes.Value.Length -gt 1 -and $forceIncludes.Value[0].Contains("PCH")) {
      # Swap the first two force includes for an unreal project. The first is the forced PCH
      # which *should* always be first, but causes a clang failure (invalid PCH) if clang tries to
      # use it.
      $temp = $forceIncludes.Value[0]
      $forceIncludes.Value[0] = $forceIncludes.Value[1]
      $forceIncludes.Value[1] = $temp
    }
  }

  if ($disableMacroWarning)
  {
    # Disable macro redefinition warnings. We are redefining __has_builtin, which is dodgy, but
    # works in the Unreal case.
    $preprocessorDefinitions.Value += @('-Wno-builtin-macro-redefined')
  }

  # For an unreal project we have to forcibly add a few things to make it work with clang-tidy
  $preprocessorDefinitions.Value += @(
    # Unreal engine is not set up for building with the clang compiler.
    # Firstly, it's missing the built in function __builtin_ia32_tpause()
    # We fake it so that it can do so for analysis purposes.
    '-D__has_builtin(...)=1',
    '-D__builtin_ia32_tpause(...)'
  )

  if ($disableMetaMacros)
  {
    $preprocessorDefinitions.Value += @(
        # Unreal meta parser macros can prevent parsing when we don't have the correct includes.
        # We use preproessor macros to mask them.
        '-DGENERATED_BODY(...)=',
        '-DRIGVM_METHOD(...)=',
        '-DUCLASS(...)=',
        '-DUDELEGATE(...)=',
        '-DUE_DEPRECATED(...)=',
        '-DUENUM(...)=',
        '-DUFUNCTION(...)=',
        '-DUINTERFACE(...)=',
        '-DUMETA(...)=',
        '-DUPARAM(...)=',
        '-DUPROPERTY(...)=',
        '-DUSTRUCT(...)='
    )
  }
}
