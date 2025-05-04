<#
    Microsoft.TeamFoundation.DistributedTask.Task.Deployment.Azure.psm1
#>

function Get-AzureCmdletsVersion
{
    $module = Get-Module AzureRM
    if($module)
    {
        return ($module).Version
    }
    return (Get-Module Azure).Version
}

function Get-AzureVersionComparison
{
    param
    (
        [System.Version] [Parameter(Mandatory = $true)]
        $AzureVersion,

        [System.Version] [Parameter(Mandatory = $true)]
        $CompareVersion
    )

    $result = $AzureVersion.CompareTo($CompareVersion)

    if ($result -lt 0)
    {
        #AzureVersion is before CompareVersion
        return $false 
    }
    else
    {
        return $true
    }
}

function Set-CurrentAzureSubscription
{
    param
    (
        [String] [Parameter(Mandatory = $true)]
        $azureSubscriptionId,
        
        [String] [Parameter(Mandatory = $false)]  #publishing websites doesn't require a StorageAccount
        $storageAccount
    )

    if (Get-SelectNotRequiringDefault)
    {                
        Write-Host "Select-AzureSubscription -SubscriptionId $azureSubscriptionId"
        # Assign return value to $newSubscription so it isn't implicitly returned by the function
        $newSubscription = Select-AzureSubscription -SubscriptionId $azureSubscriptionId        
    }
    else
    {
        Write-Host "Select-AzureSubscription -SubscriptionId $azureSubscriptionId -Default"
        # Assign return value to $newSubscription so it isn't implicitly returned by the function
        $newSubscription = Select-AzureSubscription -SubscriptionId $azureSubscriptionId -Default
    }
    
    if ($storageAccount)
    {
        Write-Host "Set-AzureSubscription -SubscriptionId $azureSubscriptionId -CurrentStorageAccountName $storageAccount"
        Set-AzureSubscription -SubscriptionId $azureSubscriptionId -CurrentStorageAccountName $storageAccount
    }
}

function Set-CurrentAzureRMSubscription
{
    param
    (
        [String] [Parameter(Mandatory = $true)]
        $azureSubscriptionId,
        
        [String]
        $tenantId
    )

    if([String]::IsNullOrWhiteSpace($tenantId))
    {
        Write-Host "Select-AzureRMSubscription -SubscriptionId $azureSubscriptionId"
        # Assign return value to $newSubscription so it isn't implicitly returned by the function
        $newSubscription = Select-AzureRMSubscription -SubscriptionId $azureSubscriptionId
    }
    else
    {
        Write-Host "Select-AzureRMSubscription -SubscriptionId $azureSubscriptionId -tenantId $tenantId"
        # Assign return value to $newSubscription so it isn't implicitly returned by the function
        $newSubscription = Select-AzureRMSubscription -SubscriptionId $azureSubscriptionId -tenantId $tenantId
    }
}

function Get-SelectNotRequiringDefault
{
    $azureVersion = Get-AzureCmdletsVersion

    #0.8.15 make the Default parameter for Select-AzureSubscription optional
    $versionRequiring = New-Object -TypeName System.Version -ArgumentList "0.8.15"

    $result = Get-AzureVersionComparison -AzureVersion $azureVersion -CompareVersion $versionRequiring

    return $result
}

function Get-RequiresEnvironmentParameter
{
    $azureVersion = Get-AzureCmdletsVersion

    #0.8.8 requires the Environment parameter for Set-AzureSubscription
    $versionRequiring = New-Object -TypeName System.Version -ArgumentList "0.8.8"

    $result = Get-AzureVersionComparison -AzureVersion $azureVersion -CompareVersion $versionRequiring

    return $result
}

function Set-UserAgent
{
    if ($env:AZURE_HTTP_USER_AGENT)
    {
        try
        {
            [Microsoft.Azure.Common.Authentication.AzureSession]::ClientFactory.AddUserAgent($UserAgent)
        }
        catch
        {
        Write-Verbose "Set-UserAgent failed with exception message: $_.Exception.Message"
        }
    }
}

function Initialize-AzureSubscription 
{
    param
    (
        [String] [Parameter(Mandatory = $true)]
        $ConnectedServiceName,

        [String] [Parameter(Mandatory = $false)]  #publishing websites doesn't require a StorageAccount
        $StorageAccount
    )

    Import-Module "Microsoft.TeamFoundation.DistributedTask.Task.Internal"

    Write-Host ""
    Write-Host "Get-ServiceEndpoint -Name $ConnectedServiceName -Context $distributedTaskContext"
    $serviceEndpoint = Get-ServiceEndpoint -Name "$ConnectedServiceName" -Context $distributedTaskContext
    if ($serviceEndpoint -eq $null)
    {
        throw "A Connected Service with name '$ConnectedServiceName' could not be found.  Ensure that this Connected Service was successfully provisioned using services tab in Admin UI."
    }

    $x509Cert = $null
    if ($serviceEndpoint.Authorization.Scheme -eq 'Certificate')
    {
        $subscription = $serviceEndpoint.Data.SubscriptionName
        Write-Host "subscription= $subscription"

        Write-Host "Get-X509Certificate -CredentialsXml <xml>"
        $x509Cert = Get-X509Certificate -ManagementCertificate $serviceEndpoint.Authorization.Parameters.Certificate
        if (!$x509Cert)
        {
            throw "There was an error with the Azure management certificate used for deployment."
        }

        $azureSubscriptionId = $serviceEndpoint.Data.SubscriptionId
        $azureSubscriptionName = $serviceEndpoint.Data.SubscriptionName
        $azureServiceEndpoint = $serviceEndpoint.Url

		$EnvironmentName = "AzureCloud"
		if( $serviceEndpoint.Data.Environment )
        {
            $EnvironmentName = $serviceEndpoint.Data.Environment
        }

        Write-Host "azureSubscriptionId= $azureSubscriptionId"
        Write-Host "azureSubscriptionName= $azureSubscriptionName"
        Write-Host "azureServiceEndpoint= $azureServiceEndpoint"
    }
    elseif ($serviceEndpoint.Authorization.Scheme -eq 'UserNamePassword')
    {
        $username = $serviceEndpoint.Authorization.Parameters.UserName
        $password = $serviceEndpoint.Authorization.Parameters.Password
        $azureSubscriptionId = $serviceEndpoint.Data.SubscriptionId
        $azureSubscriptionName = $serviceEndpoint.Data.SubscriptionName

        Write-Host "Username= $username"
        Write-Host "azureSubscriptionId= $azureSubscriptionId"
        Write-Host "azureSubscriptionName= $azureSubscriptionName"

        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $psCredential = New-Object System.Management.Automation.PSCredential ($username, $securePassword)
        
        if(Get-Module Azure)
        {
             Write-Host "Add-AzureAccount -Credential `$psCredential"
             $azureAccount = Add-AzureAccount -Credential $psCredential
        }

        if(Get-module -Name Azurerm.profile -ListAvailable)
        {
             Write-Host "Add-AzureRMAccount -Credential `$psCredential"
             $azureRMAccount = Add-AzureRMAccount -Credential $psCredential
        }

        if (!$azureAccount -and !$azureRMAccount)
        {
            throw "There was an error with the Azure credentials used for deployment."
        }

        if($azureAccount)
        {
            Set-CurrentAzureSubscription -azureSubscriptionId $azureSubscriptionId -storageAccount $StorageAccount
        }

        if($azureRMAccount)
        {
            Set-CurrentAzureRMSubscription -azureSubscriptionId $azureSubscriptionId
        }
    }
    elseif ($serviceEndpoint.Authorization.Scheme -eq 'ServicePrincipal')
    {
        $servicePrincipalId = $serviceEndpoint.Authorization.Parameters.ServicePrincipalId
        $servicePrincipalKey = $serviceEndpoint.Authorization.Parameters.ServicePrincipalKey
        $tenantId = $serviceEndpoint.Authorization.Parameters.TenantId
        $azureSubscriptionId = $serviceEndpoint.Data.SubscriptionId
        $azureSubscriptionName = $serviceEndpoint.Data.SubscriptionName

        Write-Host "tenantId= $tenantId"
        Write-Host "azureSubscriptionId= $azureSubscriptionId"
        Write-Host "azureSubscriptionName= $azureSubscriptionName"

        $securePassword = ConvertTo-SecureString $servicePrincipalKey -AsPlainText -Force
        $psCredential = New-Object System.Management.Automation.PSCredential ($servicePrincipalId, $securePassword)

        $currentVersion =  Get-AzureCmdletsVersion
        $minimumAzureVersion = New-Object System.Version(0, 9, 9)
        $isPostARMCmdlet = Get-AzureVersionComparison -AzureVersion $currentVersion -CompareVersion $minimumAzureVersion

        if($isPostARMCmdlet)
        {
             if(!(Get-module -Name Azurerm.profile -ListAvailable))
             {
                  throw "AzureRM Powershell module is not found. SPN based authentication is failed."
             }

             Write-Host "Add-AzureRMAccount -ServicePrincipal -Tenant $tenantId -Credential $psCredential"
             $azureRMAccount = Add-AzureRMAccount -ServicePrincipal -Tenant $tenantId -Credential $psCredential 
        }
        else
        {
             Write-Host "Add-AzureAccount -ServicePrincipal -Tenant `$tenantId -Credential `$psCredential"
             $azureAccount = Add-AzureAccount -ServicePrincipal -Tenant $tenantId -Credential $psCredential
        }

        if (!$azureAccount -and !$azureRMAccount)
        {
            throw "There was an error with the service principal used for deployment."
        }

        if($azureAccount)
        {
            Set-CurrentAzureSubscription -azureSubscriptionId $azureSubscriptionId -storageAccount $StorageAccount
        }

        if($azureRMAccount)
        {
            Set-CurrentAzureRMSubscription -azureSubscriptionId $azureSubscriptionId -tenantId $tenantId
        }
    }
    else
    {
        throw "Unsupported authorization scheme for azure endpoint = " + $serviceEndpoint.Authorization.Scheme
    }

    if ($x509Cert)
    {
        if(!(Get-Module Azure))
        {
             throw "Azure Powershell module is not found. Certificate based authentication is failed."
        }

        if (Get-RequiresEnvironmentParameter)
        {
            if ($StorageAccount)
            {
                Write-Host "Set-AzureSubscription -SubscriptionName $azureSubscriptionName -SubscriptionId $azureSubscriptionId -Certificate <cert> -CurrentStorageAccountName $StorageAccount -Environment $EnvironmentName"
                Set-AzureSubscription -SubscriptionName $azureSubscriptionName -SubscriptionId $azureSubscriptionId -Certificate $x509Cert -CurrentStorageAccountName $StorageAccount -Environment $EnvironmentName
            }
            else
            {
                Write-Host "Set-AzureSubscription -SubscriptionName $azureSubscriptionName -SubscriptionId $azureSubscriptionId -Certificate <cert> -Environment $EnvironmentName"
                Set-AzureSubscription -SubscriptionName $azureSubscriptionName -SubscriptionId $azureSubscriptionId -Certificate $x509Cert -Environment $EnvironmentName
            }
        }
        else
        {
            if ($StorageAccount)
            {
                Write-Host "Set-AzureSubscription -SubscriptionName $azureSubscriptionName -SubscriptionId $azureSubscriptionId -Certificate <cert> -ServiceEndpoint $azureServiceEndpoint -CurrentStorageAccountName $StorageAccount"
                Set-AzureSubscription -SubscriptionName $azureSubscriptionName -SubscriptionId $azureSubscriptionId -Certificate $x509Cert -ServiceEndpoint $azureServiceEndpoint -CurrentStorageAccountName $StorageAccount
            }
            else
            {
                Write-Host "Set-AzureSubscription -SubscriptionName $azureSubscriptionName -SubscriptionId $azureSubscriptionId -Certificate <cert> -ServiceEndpoint $azureServiceEndpoint"
                Set-AzureSubscription -SubscriptionName $azureSubscriptionName -SubscriptionId $azureSubscriptionId -Certificate $x509Cert -ServiceEndpoint $azureServiceEndpoint
            }
        }

        Set-CurrentAzureSubscription -azureSubscriptionId $azureSubscriptionId -storageAccount $StorageAccount
    }
}

function Get-AzureModuleLocation
{
    #Locations are from Web Platform Installer
    $azureModuleFolder = ""
    $azureX86Location = "${env:ProgramFiles(x86)}\Microsoft SDKs\Azure\PowerShell\ServiceManagement\Azure\Azure.psd1"
    $azureLocation = "${env:ProgramFiles}\Microsoft SDKs\Azure\PowerShell\ServiceManagement\Azure\Azure.psd1"

    if (Test-Path($azureX86Location))
    {
        $azureModuleFolder = $azureX86Location
    }
     
    elseif (Test-Path($azureLocation))
    {
        $azureModuleFolder = $azureLocation
    }

    $azureModuleFolder
}

function Import-AzurePowerShellModule
{
    # Try this to ensure the module is actually loaded...
    $moduleLoaded = $false
    $azureFolder = Get-AzureModuleLocation

    if(![string]::IsNullOrEmpty($azureFolder))
    {
        Write-Host "Looking for Azure PowerShell module at $azureFolder"
        Import-Module -Name $azureFolder -Global:$true
        $moduleLoaded = $true
    }
    else
    {
        if(Get-Module -Name "Azure" -ListAvailable)
        {
            Write-Host "Importing Azure Powershell module."
            Import-Module "Azure"
            $moduleLoaded = $true
        }

        if(Get-Module -Name "AzureRM" -ListAvailable)
        {
            Write-Host "Importing AzureRM Powershell module."
            Import-Module "AzureRM"
            $moduleLoaded = $true
        }
    }

    if(!$moduleLoaded)
    {
         throw "Windows Azure Powershell (Azure.psd1) and Windows AzureRM Powershell (AzureRM.psd1) modules are not found. Retry after restart of VSO Agent service, if modules are recently installed."
    }
}

function Initialize-AzurePowerShellSupport
{
    param
    (
        [String] [Parameter(Mandatory = $true)]
        $ConnectedServiceName,

        [String] [Parameter(Mandatory = $false)]  #publishing websites doesn't require a StorageAccount
        $StorageAccount
    )

    #Ensure we can call the Azure module/cmdlets
    Import-AzurePowerShellModule

    $minimumAzureVersion = "0.8.10.1"
    $minimumRequiredAzurePSCmdletVersion = New-Object -TypeName System.Version -ArgumentList $minimumAzureVersion
    $installedAzureVersion = Get-AzureCmdletsVersion
    Write-Host "AzurePSCmdletsVersion= $installedAzureVersion"

    $result = Get-AzureVersionComparison -AzureVersion $installedAzureVersion -CompareVersion $minimumRequiredAzurePSCmdletVersion
    if (!$result)
    {
        throw "The required minimum version ($minimumAzureVersion) of the Azure Powershell Cmdlets are not installed."
    }

    # Set UserAgent for Azure
    Set-UserAgent

    # Intialize the Azure subscription based on the passed in values
    Initialize-AzureSubscription -ConnectedServiceName $ConnectedServiceName -StorageAccount $StorageAccount
}
# SIG # Begin signature block
# MIIoPAYJKoZIhvcNAQcCoIIoLTCCKCkCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCAjLHErWkQVhiJ
# h63kfMHLxaqf1YYraTQRHNVPTTxRuqCCDYUwggYDMIID66ADAgECAhMzAAAEA73V
# lV0POxitAAAAAAQDMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjQwOTEyMjAxMTEzWhcNMjUwOTExMjAxMTEzWjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQCfdGddwIOnbRYUyg03O3iz19XXZPmuhEmW/5uyEN+8mgxl+HJGeLGBR8YButGV
# LVK38RxcVcPYyFGQXcKcxgih4w4y4zJi3GvawLYHlsNExQwz+v0jgY/aejBS2EJY
# oUhLVE+UzRihV8ooxoftsmKLb2xb7BoFS6UAo3Zz4afnOdqI7FGoi7g4vx/0MIdi
# kwTn5N56TdIv3mwfkZCFmrsKpN0zR8HD8WYsvH3xKkG7u/xdqmhPPqMmnI2jOFw/
# /n2aL8W7i1Pasja8PnRXH/QaVH0M1nanL+LI9TsMb/enWfXOW65Gne5cqMN9Uofv
# ENtdwwEmJ3bZrcI9u4LZAkujAgMBAAGjggGCMIIBfjAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQU6m4qAkpz4641iK2irF8eWsSBcBkw
# VAYDVR0RBE0wS6RJMEcxLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJh
# dGlvbnMgTGltaXRlZDEWMBQGA1UEBRMNMjMwMDEyKzUwMjkyNjAfBgNVHSMEGDAW
# gBRIbmTlUAXTgqoXNzcitW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8v
# d3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIw
# MTEtMDctMDguY3JsMGEGCCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDov
# L3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDEx
# XzIwMTEtMDctMDguY3J0MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIB
# AFFo/6E4LX51IqFuoKvUsi80QytGI5ASQ9zsPpBa0z78hutiJd6w154JkcIx/f7r
# EBK4NhD4DIFNfRiVdI7EacEs7OAS6QHF7Nt+eFRNOTtgHb9PExRy4EI/jnMwzQJV
# NokTxu2WgHr/fBsWs6G9AcIgvHjWNN3qRSrhsgEdqHc0bRDUf8UILAdEZOMBvKLC
# rmf+kJPEvPldgK7hFO/L9kmcVe67BnKejDKO73Sa56AJOhM7CkeATrJFxO9GLXos
# oKvrwBvynxAg18W+pagTAkJefzneuWSmniTurPCUE2JnvW7DalvONDOtG01sIVAB
# +ahO2wcUPa2Zm9AiDVBWTMz9XUoKMcvngi2oqbsDLhbK+pYrRUgRpNt0y1sxZsXO
# raGRF8lM2cWvtEkV5UL+TQM1ppv5unDHkW8JS+QnfPbB8dZVRyRmMQ4aY/tx5x5+
# sX6semJ//FbiclSMxSI+zINu1jYerdUwuCi+P6p7SmQmClhDM+6Q+btE2FtpsU0W
# +r6RdYFf/P+nK6j2otl9Nvr3tWLu+WXmz8MGM+18ynJ+lYbSmFWcAj7SYziAfT0s
# IwlQRFkyC71tsIZUhBHtxPliGUu362lIO0Lpe0DOrg8lspnEWOkHnCT5JEnWCbzu
# iVt8RX1IV07uIveNZuOBWLVCzWJjEGa+HhaEtavjy6i7MIIHejCCBWKgAwIBAgIK
# YQ6Q0gAAAAAAAzANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlm
# aWNhdGUgQXV0aG9yaXR5IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEw
# OTA5WjB+MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYD
# VQQDEx9NaWNyb3NvZnQgQ29kZSBTaWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG
# 9w0BAQEFAAOCAg8AMIICCgKCAgEAq/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+la
# UKq4BjgaBEm6f8MMHt03a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc
# 6Whe0t+bU7IKLMOv2akrrnoJr9eWWcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4D
# dato88tt8zpcoRb0RrrgOGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+
# lD3v++MrWhAfTVYoonpy4BI6t0le2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nk
# kDstrjNYxbc+/jLTswM9sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6
# A4aN91/w0FK/jJSHvMAhdCVfGCi2zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmd
# X4jiJV3TIUs+UsS1Vz8kA/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL
# 5zmhD+kjSbwYuER8ReTBw3J64HLnJN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zd
# sGbiwZeBe+3W7UvnSSmnEyimp31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3
# T8HhhUSJxAlMxdSlQy90lfdu+HggWCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS
# 4NaIjAsCAwEAAaOCAe0wggHpMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRI
# bmTlUAXTgqoXNzcitW2oynUClTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTAL
# BgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBD
# uRQFTuHqp8cx0SOJNDBaBgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jv
# c29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFf
# MDNfMjIuY3JsMF4GCCsGAQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFf
# MDNfMjIuY3J0MIGfBgNVHSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEF
# BQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1h
# cnljcHMuaHRtMEAGCCsGAQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkA
# YwB5AF8AcwB0AGEAdABlAG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn
# 8oalmOBUeRou09h0ZyKbC5YR4WOSmUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7
# v0epo/Np22O/IjWll11lhJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0b
# pdS1HXeUOeLpZMlEPXh6I/MTfaaQdION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/
# KmtYSWMfCWluWpiW5IP0wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvy
# CInWH8MyGOLwxS3OW560STkKxgrCxq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBp
# mLJZiWhub6e3dMNABQamASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJi
# hsMdYzaXht/a8/jyFqGaJ+HNpZfQ7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYb
# BL7fQccOKO7eZS/sl/ahXJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbS
# oqKfenoi+kiVH6v7RyOA9Z74v2u3S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sL
# gOppO6/8MO0ETI7f33VtY5E90Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtX
# cVZOSEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCGg0wghoJAgEBMIGVMH4x
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01p
# Y3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAAQDvdWVXQ87GK0AAAAA
# BAMwDQYJYIZIAWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQw
# HAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIAHa
# dRrVSWFOq4HKyCAERjQfzWAOXG6qkDS+FjQ3FRWtMEIGCisGAQQBgjcCAQwxNDAy
# oBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20wDQYJKoZIhvcNAQEBBQAEggEAI058xeUn0WupVBm2D3KrdJPMsKSXN9S+xg5h
# c/Qmy1E+MNnR42Z5J3V9xXBhZgWkiJlF1eWMQRH0oE5939X/7lCyQfpVZdcGfCzr
# aRMALzhRdHCzsIGMKprd3MgJbYCCVs5oJl6lLf3Vj4Vfnaj6nQaiyIhV8xPfoNLH
# f0p6YA2RHyFZWQh5TTU2XhxVnPtCTIip9hf6b4Lyxt/9d/kec68pIvlB/PvGmE4d
# lkFYly2GLqxdbgV65ogfCRsxfUomjYgCNTV7CpOgitL0EO94gmvt5vyj3t6w2AB0
# RBZqr0zGYl1YbBBdXHXIcnI2Og0wgXU6QMLhwPtgasyI6W/5zKGCF5cwgheTBgor
# BgEEAYI3AwMBMYIXgzCCF38GCSqGSIb3DQEHAqCCF3AwghdsAgEDMQ8wDQYJYIZI
# AWUDBAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGE
# WQoDATAxMA0GCWCGSAFlAwQCAQUABCCtAs/jspHISGPS9dPgfppgAtdGRYQTsfig
# 04v3FRZPuwIGZ/e86B+9GBMyMDI1MDQxNTA4MTgwNC44NzNaMASAAgH0oIHRpIHO
# MIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
# UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQL
# ExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxk
# IFRTUyBFU046QTkzNS0wM0UwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1l
# LVN0YW1wIFNlcnZpY2WgghHtMIIHIDCCBQigAwIBAgITMwAAAgy5ZOM1nOz0rgAB
# AAACDDANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAx
# MDAeFw0yNTAxMzAxOTQzMDBaFw0yNjA0MjIxOTQzMDBaMIHLMQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1l
# cmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046QTkzNS0w
# M0UwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2Uw
# ggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDKAVYmPeRtga/U6jzqyqLD
# 0MAool23gcBN58+Z/XskYwNJsZ+O+wVyQYl8dPTK1/BC2xAic1m+JvckqjVaQ32K
# mURsEZotirQY4PKVW+eXwRt3r6szgLuic6qoHlbXox/l0HJtgURkzDXWMkKmGSL7
# z8/crqcvmYqv8t/slAF4J+mpzb9tMFVmjwKXONVdRwg9Q3WaPZBC7Wvoi7PRIN2j
# gjSBnHYyAZSlstKNrpYb6+Gu6oSFkQzGpR65+QNDdkP4ufOf4PbOg3fb4uGPjI8E
# PKlpwMwai1kQyX+fgcgCoV9J+o8MYYCZUet3kzhhwRzqh6LMeDjaXLP701SXXiXc
# 2ZHzuDHbS/sZtJ3627cVpClXEIUvg2xpr0rPlItHwtjo1PwMCpXYqnYKvX8aJ8na
# wT9W8FUuuyZPG1852+q4jkVleKL7x+7el8ETehbdkwdhAXyXimaEzWetNNSmG/Kf
# HAp9czwsL1vKr4Rgn+pIIkZHuomdf5e481K+xIWhLCPdpuV87EqGOK/jbhOnZEqw
# dvA0AlMaLfsmCemZmupejaYuEk05/6cCUxgF4zCnkJeYdMAP+9Z4kVh7tzRFsw/l
# ZSl2D7EhIA6Knj6RffH2k7YtSGSv86CShzfiXaz9y6sTu8SGqF6ObL/eu/DkivyV
# oCfUXWLjiSJsrS63D0EHHQIDAQABo4IBSTCCAUUwHQYDVR0OBBYEFHUORSH/sB/r
# Q/beD0l5VxQ706GIMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8G
# A1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMv
# Y3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBs
# BggrBgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0
# LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUy
# MDIwMTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUH
# AwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4ICAQDZMPr4gVmwwf4G
# MB5ZfHSr34uhug6yzu4HUT+JWMZqz9uhLZBoX5CPjdKJzwAVvYoNuLmS0+9lA5S7
# 4rvKqd/u9vp88VGk6U7gMceatdqpKlbVRdn2ZfrMcpI4zOc6BtuYrzJV4cEs1YmX
# 95uiAxaED34w02BnfuPZXA0edsDBbd4ixFU8X/1J0DfIUk1YFYPOrmwmI2k16u6T
# cKO0YpRlwTdCq9vO0eEIER1SLmQNBzX9h2ccCvtgekOaBoIQ3ZRai8Ds1f+wcKCP
# zD4qDX3xNgvLFiKoA6ZSG9S/yOrGaiSGIeDy5N9VQuqTNjryuAzjvf5W8AQp31hV
# 1GbUDOkbUdd+zkJWKX4FmzeeN52EEbykoWcJ5V9M4DPGN5xpFqXy9aO0+dR0UUYW
# uqeLhDyRnVeZcTEu0xgmo+pQHauFVASsVORMp8TF8dpesd+tqkkQ8VNvI20oOfnT
# fL+7ZgUMf7qNV0ll0Wo5nlr1CJva1bfk2Hc5BY1M9sd3blBkezyvJPn4j0bfOOrC
# YTwYsNsjiRl/WW18NOpiwqciwFlUNqtWCRMzC9r84YaUMQ82Bywk48d4uBon5ZA8
# pXXS7jwJTjJj5USeRl9vjT98PDZyCFO2eFSOFdDdf6WBo/WZUA2hGZ0q+J7j140f
# bXCfOUIm0j23HaAV0ckDS/nmC/oF1jCCB3EwggVZoAMCAQICEzMAAAAVxedrngKb
# SZkAAAAAABUwDQYJKoZIhvcNAQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmlj
# YXRlIEF1dGhvcml0eSAyMDEwMB4XDTIxMDkzMDE4MjIyNVoXDTMwMDkzMDE4MzIy
# NVowfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UE
# AxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQDk4aZM57RyIQt5osvXJHm9DtWC0/3unAcH0qlsTnXI
# yjVX9gF/bErg4r25PhdgM/9cT8dm95VTcVrifkpa/rg2Z4VGIwy1jRPPdzLAEBjo
# YH1qUoNEt6aORmsHFPPFdvWGUNzBRMhxXFExN6AKOG6N7dcP2CZTfDlhAnrEqv1y
# aa8dq6z2Nr41JmTamDu6GnszrYBbfowQHJ1S/rboYiXcag/PXfT+jlPP1uyFVk3v
# 3byNpOORj7I5LFGc6XBpDco2LXCOMcg1KL3jtIckw+DJj361VI/c+gVVmG1oO5pG
# ve2krnopN6zL64NF50ZuyjLVwIYwXE8s4mKyzbnijYjklqwBSru+cakXW2dg3viS
# kR4dPf0gz3N9QZpGdc3EXzTdEonW/aUgfX782Z5F37ZyL9t9X4C626p+Nuw2TPYr
# bqgSUei/BQOj0XOmTTd0lBw0gg/wEPK3Rxjtp+iZfD9M269ewvPV2HM9Q07BMzlM
# jgK8QmguEOqEUUbi0b1qGFphAXPKZ6Je1yh2AuIzGHLXpyDwwvoSCtdjbwzJNmSL
# W6CmgyFdXzB0kZSU2LlQ+QuJYfM2BjUYhEfb3BvR/bLUHMVr9lxSUV0S2yW6r1AF
# emzFER1y7435UsSFF5PAPBXbGjfHCBUYP3irRbb1Hode2o+eFnJpxq57t7c+auIu
# rQIDAQABo4IB3TCCAdkwEgYJKwYBBAGCNxUBBAUCAwEAATAjBgkrBgEEAYI3FQIE
# FgQUKqdS/mTEmr6CkTxGNSnPEP8vBO4wHQYDVR0OBBYEFJ+nFV0AXmJdg/Tl0mWn
# G1M1GelyMFwGA1UdIARVMFMwUQYMKwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEW
# M2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5
# Lmh0bTATBgNVHSUEDDAKBggrBgEFBQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMAdQBi
# AEMAQTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV
# 9lbLj+iiXGJo0T2UkFvXzpoYxDBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3Js
# Lm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAx
# MC0wNi0yMy5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8v
# d3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2
# LTIzLmNydDANBgkqhkiG9w0BAQsFAAOCAgEAnVV9/Cqt4SwfZwExJFvhnnJL/Klv
# 6lwUtj5OR2R4sQaTlz0xM7U518JxNj/aZGx80HU5bbsPMeTCj/ts0aGUGCLu6WZn
# OlNN3Zi6th542DYunKmCVgADsAW+iehp4LoJ7nvfam++Kctu2D9IdQHZGN5tggz1
# bSNU5HhTdSRXud2f8449xvNo32X2pFaq95W2KFUn0CS9QKC/GbYSEhFdPSfgQJY4
# rPf5KYnDvBewVIVCs/wMnosZiefwC2qBwoEZQhlSdYo2wh3DYXMuLGt7bj8sCXgU
# 6ZGyqVvfSaN0DLzskYDSPeZKPmY7T7uG+jIa2Zb0j/aRAfbOxnT99kxybxCrdTDF
# NLB62FD+CljdQDzHVG2dY3RILLFORy3BFARxv2T5JL5zbcqOCb2zAVdJVGTZc9d/
# HltEAY5aGZFrDZ+kKNxnGSgkujhLmm77IVRrakURR6nxt67I6IleT53S0Ex2tVdU
# CbFpAUR+fKFhbHP+CrvsQWY9af3LwUFJfn6Tvsv4O+S3Fb+0zj6lMVGEvL8CwYKi
# excdFYmNcP7ntdAoGokLjzbaukz5m/8K6TT4JDVnK+ANuOaMmdbhIurwJ0I9JZTm
# dHRbatGePu1+oDEzfbzL6Xu/OHBE0ZDxyKs6ijoIYn/ZcGNTTY3ugm2lBRDBcQZq
# ELQdVTNYs6FwZvKhggNQMIICOAIBATCB+aGB0aSBzjCByzELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJp
# Y2EgT3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOkE5MzUtMDNF
# MC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMK
# AQEwBwYFKw4DAhoDFQDvu8hkhEMt5Z8Ldefls7z1LVU8pqCBgzCBgKR+MHwxCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jv
# c29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA66gpxTAi
# GA8yMDI1MDQxNTAwNDE0MVoYDzIwMjUwNDE2MDA0MTQxWjB3MD0GCisGAQQBhFkK
# BAExLzAtMAoCBQDrqCnFAgEAMAoCAQACAh70AgH/MAcCAQACAhKrMAoCBQDrqXtF
# AgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSCh
# CjAIAgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBAAXbB9SaIRetPVFy/v7NzTnZ
# vqLpOux/P6la1AKpYVGYlp4HjVtoIdkG2EUlrV1oY8kCdZPAqM1NuAaQvqrwd/0g
# 5Tzi5GFakhsFf0e26qnyDjfTSnMLttL3ajz43P9nes5sLdIs6GcnOCps7xl9wAR9
# yFXI59bscXnTUSLWt3TA0MBVDld5ryDhXN9foHKQZZcG5dT8suYNF2kGFUVY8tan
# Vq9vU1AZhO9FM3c86D66i65qDfoOdLybqRlCxTrcte7r7PyvsUtDLMjBD7cfz0dv
# VcT4KyrT1NupPm3oLLRnfARnwfF2KneJrqpVd0NMQflVJFiIUm+zUgladSH2uoox
# ggQNMIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAA
# Agy5ZOM1nOz0rgABAAACDDANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkD
# MQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCC6UdI3+/9N4YsiKAC9AGlY
# 8XKVlFR2SNOcqLc317GIRDCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EINUo
# 17cFMZN46MI5NfIAg9Ux5cO5xM9inre5riuOZ8ItMIGYMIGApH4wfDELMAkGA1UE
# BhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAc
# BgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0
# IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIMuWTjNZzs9K4AAQAAAgwwIgQgf9WU
# fP21NxlHnp+dBNtnN20gEx41mtUuWO74eHYOPOMwDQYJKoZIhvcNAQELBQAEggIA
# HG2U4FU6mz7clt70T+ROAQeiba2rWKsrDa4SoMs7O3fV5S5sjKUQW2cu/f5jfPe1
# HzhmxWcFa4C/DCkrULl4q/LhBwXPAJ8fY8HrRdQsX5koOz5uhOkB7E8E5Ns7SgLC
# 36CEHKa2cKfRgnn1KqktJ+XMdzVlCvRbYzPWmzvEV3GBU+Qd0PJNt78ZcaIjNkJ9
# fl1DorBJGryDf1VzCSZC+u28PGfkyptpg9qEuNb9HyvMMOfBf5dVgxv+R6vy24Oq
# zItqJGNssvYGvHXzFyywO2Hebv6wn8GaOCjSsqde/RgDdtpIq2xejqfU4vJH8pzY
# XUV64M8JpHmiVu0tR7+srnq1ITWHBoWmviKJU7+Etk8NNn7t3rn3jBx9EFR5bzd7
# haa5/axPG1y2MHMdunxGXVx1TqbmxvxcMYefj9fs2OrN9+0SXvqqKqfeXIB6NF1v
# CWOTUIUD40XbGKkjGCtk+xFN3wOkCRf+0sGK4MeIzmddDL9OiNjGOMHpuTTnAOX7
# Pbc5JZG69RgauZfO3j/0vz4bFVSa2+j+s7hU8BCFehIGydAFn5Y7n1M7RfhY42uA
# uKPqX8pDMkZkLr6Hr4VrlCCQlodegv7+3AxUJ/tbRcRIq+C556eyLktAWaJVAlpC
# 4pzBOAGr8JH2JL/+Q9oeYY9p4ddoeTjS0jPz8x46KvY=
# SIG # End signature block
