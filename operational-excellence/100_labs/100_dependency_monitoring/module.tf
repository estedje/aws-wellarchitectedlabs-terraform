

data "aws_caller_identity" "current" {
}


variable "availability_zone" {
  description = "The Availability Zone in which resources are launched."
  type = string
  default = "eu-west-1c"
}


variable "bucket_name" {
  description = "A name for the S3 bucket that is created. Note that the namespace for S3 buckets is global so the bucket name you enter here has to be globally unique."
  type = string
  default = "dep-mon-bucket"
}



variable "notification_email" {
  description = "The email address to which CloudWatch Alarm notifications are published."
  type = string
}


resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"
  tags = [{"Key": "Name", "Value": "WA-Lab-VPC"}]
}


resource "aws_subnet" "subnet" {
  availability_zone = var.availability_zone
  cidr_block = "10.0.0.0/24"
  vpc_id = aws_vpc.vpc.arn
  map_public_ip_on_launch = "true"
  tags = [{"Key": "Name", "Value": "WA-Lab-Subnet"}]
}


resource "aws_internet_gateway" "internet_gateway" {
  tags = [{"Key": "Name", "Value": "WA-Lab-InternetGateway"}]
}


resource "aws_vpn_gateway_attachment" "vpc_gateway_attachment" {
  vpc_id = aws_vpc.vpc.arn
}


resource "aws_route_table" "route_table" {
  vpc_id = aws_vpc.vpc.arn
  tags = [{"Key": "Name", "Value": "WA-Lab-RouteTable"}]
}


resource "aws_route" "route" {
  route_table_id = aws_route_table.route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.internet_gateway.id
}


resource "aws_route_table_association" "route_table_association" {
  route_table_id = aws_route_table.route_table.id
  subnet_id = aws_subnet.subnet.id
}

data "aws_ami" "amzn2" {
  most_recent = true

  filter {
    name   = "name"
    values = ["/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
    
resource "aws_instance" "instance" {
  ami = data.aws_ami.amzn2.id
  instance_type = "t2.micro"
  iam_instance_profile = aws_iam_instance_profile.instance_profile.arn
  subnet_id = aws_subnet.subnet.id
  user_data = <<EOT
#!/bin/bash -x
echo "test" >> /home/ec2-user/data.txt
echo "#!/bin/bash" >> /home/ec2-user/data-write.sh
echo "while true" >> /home/ec2-user/data-write.sh
echo "do" >> /home/ec2-user/data-write.sh
echo "aws s3api put-object --bucket ", var.bucket_name, " --key data.txt --body /home/ec2-user/data.txt" >> /home/ec2-user/data-write.sh
echo "sleep 50" >> /home/ec2-user/data-write.sh
echo "done" >> /home/ec2-user/data-write.sh
chmod +x /home/ec2-user/data-write.sh
sh /home/ec2-user/data-write.sh &
EOT
  tags = [{"Key": "Name", "Value": "WA-Lab-Instance"}]
}


resource "aws_iam_instance_profile" "instance_profile" {
  name = "WA-Lab-Instance-Profile"
  role = [aws_iam_role.instance_role.arn]
}


resource "aws_iam_role" "instance_role" {
  name = "WA-Lab-InstanceRole"
  assume_role_policy = {
    Version = "2012-10-17"
    Statement = [{"Effect": "Allow", "Principal": {"Service": "ec2.amazonaws.com"}, "Action": "sts:AssumeRole"}]
  }
  force_detach_policies = [{"PolicyName": "S3PutObject", "PolicyDocument": {"Version": "2012-10-17", "Statement": [{"Effect": "Allow", "Action": "s3:PutObject", "Resource": "join(", ["arn:aws:s3:::", var.bucket_name, "/*"])"}]}}]
}


resource "aws_s3_bucket" "bucket" {
  bucket = var.bucket_name
}
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.data_read_function.arn
    events              = ["s3:ObjectCreated:Put"]
  }

  depends_on = [aws_lambda_permission.allow_bucket]
}
    

resource "aws_sns_topic" "sns_topic" {
  name = "WA-Lab-Dependency-Notification"
}
    
resource "aws_sns_topic_subscription" "user_updates_sqs_target" {
  topic_arn = aws_sns_topic.sns_topic.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

data "archive_file" "zip_the_python_code" {
  type         = "zip"
  source_file  = "${path.module}/data_read_function/index.py"
  output_path  = "${path.module}/data_read_function/code.zip"
}
resource "aws_lambda_function" "data_read_function" {
  function_name = "WA-Lab-DataReadFunction"
  handler = "index.lambda_handler"
  role = aws_iam_role.data_read_lambda_role.arn
  runtime = "python3.7"
  filename = "${path.module}/data_read_function/code.zip"
}
data "archive_file" "zip_the_python_code" {
  type        = "zip"
  source_file   = "${path.module}/ops_item_function/index.py"
  output_path = "${path.module}/ops_item_function/code.zip"
}

resource "aws_lambda_function" "ops_item_function" {
  function_name = "WA-Lab-OpsItemFunction"
  handler = "index.lambda_handler"
  role = aws_iam_role.ops_item_lambda_role.arn
  runtime = "python3.7"
  filename = "${path.module}/ops_item_function/code.zip"
}


resource "aws_iam_role" "data_read_lambda_role" {
  name = "WA-Lab-DataReadLambdaRole"
  assume_role_policy = {
    Version = "2012-10-17"
    Statement = [{"Effect": "Allow", "Principal": {"Service": "lambda.amazonaws.com"}, "Action": "sts:AssumeRole"}]       
  }
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]
  force_detach_policies = [{"PolicyName": "LambdaPolicy", "PolicyDocument": {"Version": "2012-10-17", "Statement": [{"Sid": "VisualEditor0", "Effect": "Allow", "Action": "s3:DeleteObject", "Resource": "join(", ["arn:aws:s3:::", var.bucket_name, "/*"])"}]}}]
}


resource "aws_iam_role" "ops_item_lambda_role" {
  name = "WA-Lab-OpsItemLambdaRole"
  assume_role_policy = {
    Version = "2012-10-17"
    Statement = [{"Effect": "Allow", "Principal": {"Service": "lambda.amazonaws.com"}, "Action": "sts:AssumeRole"}]       
  }
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]
  force_detach_policies = [{"PolicyName": "LambdaPolicy", "PolicyDocument": {"Version": "2012-10-17", "Statement": [{"Sid": "VisualEditor0", "Effect": "Allow", "Action": "ssm:CreateOpsItem", "Resource": "*"}]}}]
}


resource "aws_lambda_permission" "data_read_lambda_permission" {
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.data_read_function.arn
  principal = "s3.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
  source_arn = join(", ["arn:aws:s3:::", var.bucket_name])
}


output "sns_topic" {
  description = "The SNS Topic you subscribed to."
  value = aws_sns_topic.sns_topic.id
}


output "data_read_function" {
  description = "The Lambda function that gets invoked when an object is uploaded to S3."
  value = aws_lambda_function.data_read_function.arn
}
