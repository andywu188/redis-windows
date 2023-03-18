#requires -Version 5

param(
	[Parameter(Position = 0)]
	$RedisVersion = "7.0.9.0",

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
		. $Nuget pack nuget\redis.windows.redist.nuspec -NoPackageAnalysis -Version $RedisVersion -Properties "Configuration=Release;Platform=$arch;" -OutputDirectory bin
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

	DownloadDependencies

	Write-Diagnostic("Redis Version: $RedisVersion")
	Write-Diagnostic("Enabled Architectures")

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
