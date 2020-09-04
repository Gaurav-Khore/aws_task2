provider "aws" {
  region     = "ap-south-1"
  profile    = "terra_use"
}
/*
resource "aws_key_pair" "deployer" {
  key_name   = "terra-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEArZE7lTuN0TsZZp/+nSz5/0MQNT7kusU/DzW9rmK/3r3IXqoeUNpv6rQV8iq701yzkjMCr/tLnCuHeDkK6qdqqcq+rcLyMN4j/ucsGYS2ckly+/lNjxvsdIf5mjpbDB9jDUaYtaS5KrSdZQE6JzrEm7iIjQLwtOefVDZ2ZvyR41FJbFTj4E/iWH8w1Ne0H+Cp32YVgCBNiWvW8Q/hRe0qB385rb+HWAnIAvZoL0dmVbRtvQJ7uuKhz2+BGWXD1gaG1+ky48BHAG/Q+nRyF7iu6BJUyEl9v1etGGGJP6zPfY894892Q+2ugrX0qvCPFub0BQaZgmqOK5G4WR5RFUd9oQ== rsa-key-20200902"
}
*/
resource "aws_security_group" "allow_ssh_http" {
  /*depends_on = [
    aws_key_pair.deployer,
  ]*/

  name        = "allow_ssh_http"
  description = "Allow http inbound traffic"
  vpc_id      = "vpc-aef7eac6"

  ingress {
    description = "http from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "ssh from VPC"
    from_port   = 22
    to_port     = 22
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
    Name = "task1_allow_http_ssh"
  }
}

resource "aws_security_group" "allow_nfs" {
  depends_on = [
    aws_security_group.allow_ssh_http,
  ]


  name        = "allow_nfs"
  description = "Allow http inbound traffic"
  vpc_id      = "vpc-aef7eac6"
  ingress {
    description = "nfs from VPC"
    from_port   = 2049
    to_port     = 2049
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
    Name = "task1_nfs"
  }
}
resource "aws_instance" "inst" {
  depends_on = [
    aws_security_group.allow_nfs,
  ]
  ami           = "ami-0a780d5bac870126a"
  instance_type = "t2.micro"
  availability_zone = "ap-south-1a"
  key_name = "red_key"
  security_groups = ["allow_ssh_http"]
   connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("C:/Users/HP/Downloads/red_key.pem")
    host     = aws_instance.inst.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "sudo yum install git -y",
      "sudo yum install httpd -y",
      "sudo service httpd restart",
    ]
  }
  tags = {
    Name = "task1_os"
  }
}

//here create a efs storage and abpve it create a security group
resource "aws_efs_file_system" "efs_vol" {
    depends_on = [
    aws_instance.inst,
  ]

  creation_token = "efs_task2"

  tags = {
    Name = "efs_taks2"
  }
}

resource "aws_efs_mount_target" "efs_target" {
    depends_on = [
    aws_efs_file_system.efs_vol,
  ]
  file_system_id = aws_efs_file_system.efs_vol.id
  subnet_id      = aws_instance.inst.subnet_id
  security_groups = ["${aws_security_group.allow_nfs.id}"]
}


//not needed here we will attach the EFS to the instance
resource "null_resource" "public_ip" {
     depends_on = [
    aws_efs_mount_target.efs_target,
  ]
	provisioner "local-exec" {
		command = "echo ${aws_instance.inst.public_ip} > publicip.txt"
	}
}
//needed only the part that will clone the data in var www html file
resource "null_resource" "efs_mount"  {

depends_on = [
    null_resource.public_ip,
  ]


  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("C:/Users/HP/Downloads/red_key.pem")
    host     = aws_instance.inst.public_ip
  }

provisioner "remote-exec" {
    inline = [
        "sudo yum install amazon-efs-utils nfs-utils -y",
        "sudo setenforce 0",
        "sudo mount -t nfs4 ${aws_efs_mount_target.efs_target.ip_address}:/ /var/www/html/",
        "sudo rm -rf /var/www/html/*",
        "sudo git clone https://github.com/Gaurav-Khore/terra_task1.git /var/www/html/"
    ]
  }
}


resource "aws_s3_bucket" "terra_bucket" {
  depends_on = [
    null_resource.efs_mount,
  ]
  bucket = "terrabucg"
  acl = "public-read"

  tags = {
    Name        = "terrabucg"
    Environment = "Dev"
  }
}
resource "null_resource" "git_base"  {

  depends_on = [
    aws_s3_bucket.terra_bucket,
  ]
   provisioner "local-exec" {
    working_dir="C:/Users/HP/Desktop/terra_ws/"
    command ="mkdir git_terra"
  }
  provisioner "local-exec" {
    working_dir="C:/Users/HP/Desktop/terra_ws/git_terra"
    command ="git clone https://github.com/Gaurav-Khore/terra_task1.git  C:/Users/HP/Desktop/terra_ws/git_terra"
  }
   
}



resource "aws_s3_bucket_object" "s3_upload" {
  depends_on = [
    null_resource.git_base,
  ]
  for_each = fileset("C:/Users/HP/Desktop/terra_ws/git_terra/", "*.png")

  bucket = "terrabucg"
  key    = each.value
  source = "C:/Users/HP/Desktop/terra_ws/git_terra/${each.value}"
  etag   = filemd5("C:/Users/HP/Desktop/terra_ws/git_terra/${each.value}")
  acl = "public-read"

}


locals {
  s3_origin_id = "s3-${aws_s3_bucket.terra_bucket.id}"
}

resource "aws_cloudfront_distribution" "s3_cloud" {
  depends_on = [
    aws_s3_bucket_object.s3_upload,
  ]
  origin {
    domain_name = "${aws_s3_bucket.terra_bucket.bucket_regional_domain_name}"
    origin_id   = "${local.s3_origin_id}"
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Terraform connecting s3 to the cloudfront"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400

  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Environment = "production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
resource "null_resource" "updating_code"  {

  depends_on = [
    aws_cloudfront_distribution.s3_cloud,
  ]
  connection {
    type = "ssh"
    user = "ec2-user"
    private_key = file("C:/Users/HP/Downloads/red_key.pem")
    host = aws_instance.inst.public_ip
	}
  for_each = fileset("C:/Users/HP/Desktop/terra_ws/git_terra/", "*.png")
  provisioner "remote-exec" {
    inline = [
	"sudo su << EOF",
	"echo \"<p>Image access using cloud front url</p>\" >> /var/www/html/terra_page.html",
	"echo \"<img src='http://${aws_cloudfront_distribution.s3_cloud.domain_name}/${each.value}' width='500' height='333'>\" >> /var/www/html/terra_page.html",
        "EOF"
			]
	}
	 provisioner "local-exec" {
		command = "start chrome  ${aws_instance.inst.public_ip}/terra_page.html"
	}

}