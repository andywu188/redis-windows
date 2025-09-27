#requires -Version 5

param(
	[Parameter(Position = 0)]
	$RedisVersion,

	[Parameter(Position = 1)]
	[string] $BuildArches = "win-x64"
)

Set-StrictMode -version latest
$ErrorActionPreference = "Stop";

Function WriteException($exp)
{
	write-host "Caught an exception:" -ForegroundColor Yellow -NoNewline;
	write-host " $($exp.Exception.Message)" -ForegroundColor Red;
	write-host "`tException Type: $($exp.Exception.GetType().FullName)";
	$stack = $exp.ScriptStackTrace;
	$stack = $stack.replace("`n","`n`t");
	write-host "`tStack Trace: $stack";
	throw $exp;
}

function Write-Diagnostic
{
	param(
		[Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true)]
		[string] $Message
	)

	Write-Host
	Write-Host $Message -ForegroundColor Green
	Write-Host
}

function Die
{
	param(
		[Parameter(Position = 0, ValueFromPipeline = $true)]
		[string] $Message
	)

	Write-Host
	Write-Error $Message
	exit 1

}

function Warn
{
	param(
		[Parameter(Position = 0, ValueFromPipeline = $true)]
		[string] $Message
	)

	Write-Host
	Write-Host $Message -ForegroundColor Yellow
	Write-Host

}

function Get-RedisVersion {
    <#
    .SYNOPSIS
        获取Redis版本号，优先从可执行程序读取，失败时回退到version.txt文件
    #>
    
    $versionFromExe = $null
    $versionFromFile = $null
    
    # 尝试从redis-server.exe获取版本信息
    try {
        Write-Diagnostic "尝试从redis-server.exe获取版本信息..."
        $exeVersionInfo = Get-Command .\redis-server.exe -ErrorAction Stop | Select-Object -ExpandProperty FileVersionInfo
        $versionFromExe = $exeVersionInfo.FileVersion
        
        if (-not [string]::IsNullOrWhiteSpace($versionFromExe)) {
            Write-Diagnostic "从redis-server.exe成功获取版本: $versionFromExe"
            return $versionFromExe.Trim()
        } else {
            Write-Diagnostic "redis-server.exe中未找到有效的版本信息"
        }
    } catch {
        Warn "无法从redis-server.exe读取版本信息: $($_.Exception.Message)"
    }
    
    # 如果从exe获取失败，尝试从version.txt文件读取
    try {
        Write-Diagnostic "尝试从version.txt文件获取版本信息..."
        if (Test-Path ".\version.txt" -ErrorAction SilentlyContinue) {
            $versionFromFile = Get-Content ".\version.txt" -First 1 -ErrorAction Stop
            
            if (-not [string]::IsNullOrWhiteSpace($versionFromFile)) {
                Write-Diagnostic "从version.txt成功获取版本: $versionFromFile"
                return $versionFromFile.Trim()
            } else {
                Write-Diagnostic "version.txt文件为空或第一行无内容"
            }
        } else {
            Write-Diagnostic "未找到version.txt文件"
        }
    } catch {
        Warn "读取version.txt文件失败: $($_.Exception.Message)"
    }
    
    # 如果两种方式都失败，抛出异常
    Die "无法获取Redis版本信息: 请确保redis-server.exe存在且包含版本信息，或提供有效的version.txt文件"
}

function DownloadDependencies()
{
	$folder = Join-Path $env:LOCALAPPDATA .\nuget;
	$Nuget = Join-Path $folder .\NuGet.exe
	if (-not (Test-Path $Nuget))
	{
		if (-not (Test-Path $folder))
		{
			mkdir $folder
		}
		
		Write-Diagnostic "Download nuget.exe"	
		$Client = New-Object System.Net.WebClient;
		$Client.DownloadFile('https://dist.nuget.org/win-x86-commandline/latest/nuget.exe', $Nuget);
	}
}

function Nupkg
{
	Write-Diagnostic "Building nuget package"

	$Nuget = Join-Path $env:LOCALAPPDATA .\nuget\NuGet.exe
	if (-not (Test-Path $Nuget))
	{
		Die "Please install nuget. More information available at: http://docs.nuget.org/docs/start-here/installing-nuget"
	}

	foreach ($platform in $Platforms.Values)
	{
		if(!$platform.Enabled)
		{
			continue
		}

		$arch = $platform.Arch

		# Build packages
        try {
            & $Nuget pack nuget\redis.windows.redist.nuspec -NoPackageAnalysis -Version $RedisVersion -Properties "Configuration=Release;Platform=$arch;" -OutputDirectory bin
        } catch {
            WriteException $_
        }
	}
}

try
{
	$WorkingDir = split-path -parent $MyInvocation.MyCommand.Definition;

	Write-Diagnostic "pushd $WorkingDir"
	Push-Location $WorkingDir

	$Platforms = @{
		'win-x64'=@{
			Enabled=$BuildArches.Contains('win-x64') -or $BuildArches.Contains('x64');
			NativeArch='x64';
			Arch='x64';
		};
	}

    # 获取Redis版本
    if ([string]::IsNullOrWhiteSpace($RedisVersion)) {
        $RedisVersion = Get-RedisVersion
    } else {
        Write-Diagnostic "使用参数提供的Redis版本: $RedisVersion"
    }
	
	DownloadDependencies

	Write-Diagnostic("Redis版本: $RedisVersion")
	Write-Diagnostic("启用架构: $($BuildArches)")

	Nupkg
	return;
}
catch
{
	WriteException $_;
}
finally
{
	Pop-Location
}
