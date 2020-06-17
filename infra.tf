provider "aws" {
  region = "ap-south-1"
  profile = "siddharth"
}
resource "aws_security_group" "security_group1" {
  name        = "security_group1"
  
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "security_group1"
  }
}

resource "tls_private_key" "my_private_key" {
    depends_on = [
  aws_security_group.security_group1 ]
  algorithm   = "RSA"
}
resource "aws_key_pair" "deployer" {
   depends_on = [
  tls_private_key.my_private_key ]
  key_name   = "deployer-key"
   public_key = tls_private_key.my_private_key.public_key_openssh
}
resource "aws_instance" "web1" {
   depends_on = [
  aws_key_pair.deployer ]
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  availability_zone = "ap-south-1a"
  key_name = "deployer-key"
  security_groups = [ "security_group1" ]

  tags = {
    Name = "my_terra_os"
  }
}
resource "aws_ebs_volume" "my_volume1" {
  availability_zone = aws_instance.web1.availability_zone
  size              = 1

  tags = {
    Name = "my_volume_1"
  }
}
resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdh"
  volume_id   = "${aws_ebs_volume.my_volume1.id}"
  instance_id = "${aws_instance.web1.id}"
  force_detach = true
}
resource "null_resource" "null_remote1"{
  depends_on = [
  aws_volume_attachment.ebs_att ]
  connection {
  type = "ssh"
  user = "ec2-user"
  private_key = tls_private_key.my_private_key.private_key_pem
  host = "${aws_instance.web1.public_ip}"
 }
  provisioner "remote-exec" {
  inline = [
        "sudo yum install httpd -y",
        " sudo yum install php -y ",
        " sudo yum install git -y ",
        "sudo systemctl start httpd",
        "sudo systemctl enable httpd",
        "sudo mkfs.ext4 /dev/xvdh",
        "sudo mount /dev/xvdh /var/www/html",
        "sudo rm -rf /var/www/html/*",
        "sudo git clone https://github.com/sid96020/terraform_infra.git /var/www/html/" ]
 }
}
output "my_public_ip" {
value = aws_instance.web1.public_ip
}
resource "aws_s3_bucket" "b" {
  bucket ="jarvis9602"
  acl    = "private"
  region = "ap-south-1"

  tags = {
    Name = "My_bucket"
    Environment = "Dev"
  }
}
resource "aws_s3_bucket_object" "object" {
    depends_on = [
  aws_s3_bucket.b ]
  bucket = "jarvis9602"
  key    = "tot.jpg"
  source = "C:/Users/Administrator/Desktop/tot.jpg"
}
locals {
  s3_origin_id = "myS3Origin"
}
output "b" {
  value = aws_s3_bucket.b
}
resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "Some comment"
}
output "origin_access_identity" {
  value = aws_cloudfront_origin_access_identity.origin_access_identity
}
data "aws_iam_policy_document" "s3_policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.b.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn}"]
    }
  }
  statement {
    actions   = ["s3:ListBucket"]
    resources = ["${aws_s3_bucket.b.arn}"]
    principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn}"]
    }
  }
}
resource "aws_s3_bucket_policy" "example" {
  bucket = aws_s3_bucket.b.id
  policy = data.aws_iam_policy_document.s3_policy.json
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.b.bucket_regional_domain_name
    origin_id   = local.s3_origin_id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true

 default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH" , "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}


resource "null_resource" "nulllocal1"  {


depends_on = [
    null_resource.null_remote1,
  ]

connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.my_private_key.private_key_pem
    host     = "${aws_instance.web1.public_ip}"
  }

provisioner "remote-exec" {
   inline = [
      "sudo su <<EOF",
      "sudo sed -i '5i <img src='http://${aws_cloudfront_distribution.s3_distribution.domain_name}/${aws_s3_bucket_object.object.key}' width='800' height='600' />' /var/www/html/index.html",
      "EOF"
    ]
  }
provisioner "local-exec" {
	    command = "chrome  ${aws_instance.web1.public_ip}"
  	}
}
