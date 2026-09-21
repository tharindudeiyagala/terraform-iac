---------- Terraform running Steps  -----------------------------

Use powershell - 

Set-Location C:\Data\terraform-iac\terraform

aws configure --profile lanka-deploy - added AK SK Region 

aws sts get-caller-identity    - check user can access

Copy-Item new-cinema-prod.example.tfvars lanka-cinema-prod.tfvars - copy varible example file into our cinema name

notepad .\lanka-cinema-prod.tfvars - added value to varible file 

terraform init 

terraform workspace select lanka-cinema-production 

terraform workspace show

terraform validate

--------------------------------------

$securePassword = Read-Host "Enter your MySQL master password" -AsSecureString

try {
    $env:TF_VAR_db_password = [System.Net.NetworkCredential]::new(
        "", $securePassword
    ).Password

    terraform plan "-var-file=lanka-cinema-prod.tfvars" "-out=lanka-cinema-full.tfplan"

    if ($LASTEXITCODE -ne 0) {
        throw "Planning failed. Do not run apply."
    }
}
finally {
    Remove-Item Env:TF_VAR_db_password -ErrorAction SilentlyContinue
    $securePassword.Dispose()
}

----------------------------------------------

terraform show ".\lanka-cinema-full.tfplan" - review the plan

terraform apply ".\lanka-cinema-full.tfplan" - apply the plan


------------ Terraform Destory All Resource  ---------------

terraform init
terraform workspace select lanka-cinema-production
notepad .\lanka-cinema-prod.tfvars  - deletion_protection = false ,skip_final_snapshot = true

--
$securePassword = Read-Host "Enter your existing MySQL master password" -AsSecureString

$env:TF_VAR_db_password = [System.Net.NetworkCredential]::new(
    "", $securePassword
).Password

$securePassword.Dispose()
--


terraform plan -destroy "-var-file=lanka-cinema-prod.tfvars" "-out=lanka-destroy.tfplan"

terraform apply ".\lanka-destroy.tfplan"


OR-------------


terraform destroy "-var-file=lanka-cinema-prod.tfvars" 


terraform apply "-var-file=lanka-cinema-prod.tfvars"