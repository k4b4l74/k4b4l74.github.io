$ErrorActionPreference = "Stop"

$scriptDir = $PSScriptRoot
$tests = "PerformanceVerificationBenchmarkTest,SynchronizeCodeRunEventsUseCaseTest,ImportProjectBundleUseCaseTest,ExportProjectBundleUseCaseTest,ConfiguredTextRedactionAdapterTest,AdvanceProjectPhaseUseCaseTest,OverrideProjectPhaseGateUseCaseTest,EnforceBudgetPolicyUseCaseTest"

& (Join-Path $scriptDir "mvn.bat") "-Dtest=$tests" "test"
