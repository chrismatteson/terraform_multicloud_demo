provider "aws" {
  region     = "${var.aws_region}"
}

# generate random project name
resource "random_id" "project_name" {
  byte_length = 4
}

# get the default vpc for this account/region
data "aws_vpc" "default_vpc" {
  default = true
}

# get a list of subnets in the default vpc
data "aws_subnet_ids" "default_subnets" {
  vpc_id = "${data.aws_vpc.default_vpc.id}"
}

resource "aws_instance" "multicloud-demo" {
  ami                    = "${var.webAmi}"
  instance_type          = "t2.large"
  subnet_id              = "${data.aws_subnet_ids.default_subnets.ids[0]}"
  key_name               = "${var.keyPairName}"
  vpc_security_group_ids = ["${aws_security_group.multicloud-demo_sg.id}"]

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_type = "gp2"
    volume_size = "60"
  }

  tags {
    Name    = "${random_id.project_name.hex}-multicloud-demo"
    Project = "${random_id.project_name.hex}"
  }
}

resource "aws_security_group" "multicloud-demo_sg" {
  name   = "${random_id.project_name.hex}-multicloud-demo-sg"
  vpc_id = "${data.aws_vpc.default_vpc.id}"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name    = "${random_id.project_name.hex}-sg"
    Project = "${random_id.project_name.hex}"
  }
}
