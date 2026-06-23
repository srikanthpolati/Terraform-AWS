schemaVersion: "2.2"
description: "Mandatory Application Compliance Check and Auto-Remediation - Linux"
parameters:
  Environment:
    type: String
    default: "${environment}"
  S3Bucket:
    type: String
    default: "${s3_bucket}"
  SplunkTargetVersion:
    type: String
    default: "${splunk_version}"
  QualysTargetVersion:
    type: String
    default: "${qualys_version}"
  CWAgentTargetVersion:
    type: String
    default: "${cloudwatch_version}"
  CarbonBlackTargetVersion:
    type: String
    default: "${carbonblack_version}"
  SplunkDeploymentServer:
    type: String
    default: "${splunk_deployment_server}"
  SplunkIndexName:
    type: String
    default: "${splunk_index_name}"
  QualysActivationId:
    type: String
    default: "${qualys_activation_id}"
  QualysCustomerId:
    type: String
    default: "${qualys_customer_id}"
  CarbonBlackServerUrl:
    type: String
    default: "${carbonblack_server_url}"
  CarbonBlackGroupName:
    type: String
    default: "${carbonblack_group_name}"
  AWSRegion:
    type: String
    default: "${aws_region}"
mainSteps:
  - action: aws:runShellScript
    name: CheckAndRemediateSplunk
    inputs:
      runCommand:
        - bash /tmp/ssm_scripts/splunk_compliance.sh
      workingDirectory: /tmp
      timeoutSeconds: 600
  - action: aws:runShellScript
    name: CheckAndRemediateQualys
    inputs:
      runCommand:
        - bash /tmp/ssm_scripts/qualys_compliance.sh
      workingDirectory: /tmp
      timeoutSeconds: 600
  - action: aws:runShellScript
    name: CheckAndRemediateCloudWatch
    inputs:
      runCommand:
        - bash /tmp/ssm_scripts/cloudwatch_compliance.sh
      workingDirectory: /tmp
      timeoutSeconds: 300
  - action: aws:runShellScript
    name: CheckAndRemediateCarbonBlack
    inputs:
      runCommand:
        - bash /tmp/ssm_scripts/carbonblack_compliance.sh
      workingDirectory: /tmp
      timeoutSeconds: 600
  - action: aws:runShellScript
    name: WriteSSMComplianceData
    inputs:
      runCommand:
        - bash /tmp/ssm_scripts/write_compliance.sh
      workingDirectory: /tmp
      timeoutSeconds: 120
