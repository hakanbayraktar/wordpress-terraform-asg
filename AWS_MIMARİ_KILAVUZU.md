# AWS Mimari Bileşenleri Kılavuzu

Bu dokümanda, WordPress Auto Scaling projesinde kullanılan AWS bileşenlerinin detaylı açıklamaları bulunmaktadır.

---

## İçindekiler

1. [Elastic Load Balancer (ELB)](#elastic-load-balancer-elb)
2. [Application Load Balancer (ALB)](#application-load-balancer-alb)
3. [Auto Scaling](#auto-scaling)
4. [Elastic File System (EFS)](#elastic-file-system-efs)
5. [Diğer Bileşenler](#diğer-bileşenler)

---

## Elastic Load Balancer (ELB)

### ELB Nedir?

**Elastic Load Balancer (ELB)**, AWS'nin sunduğu yük dengeleme servisidir. Gelen trafiği birden fazla hedef (EC2 instance, container, IP adresi) arasında otomatik olarak dağıtır.

### ELB'nin Temel Görevleri

1. **Trafik Dağıtımı**: Gelen istekleri birden fazla sunucu arasında dengeli şekilde dağıtır
2. **Yüksek Erişilebilirlik**: Bir sunucu çökerse, trafiği sağlıklı sunuculara yönlendirir
3. **Health Check**: Sunucuların sağlığını düzenli olarak kontrol eder
4. **SSL/TLS Sonlandırma**: HTTPS trafiklerini işler, backend'e HTTP olarak iletebilir
5. **Auto Scaling Entegrasyonu**: Yeni instance'lar otomatik olarak load balancer'a eklenir

### ELB Kullanım Senaryoları

- Web uygulamalarında yük dengeleme
- Mikroservis mimarilerinde servisler arası trafik yönetimi
- Blue-Green deployment stratejileri
- Canary deployment'lar
- Farklı bölgelerdeki (availability zone) kaynakları dengeleme

---

## ELB Türleri

AWS'de **3 farklı** Load Balancer türü bulunmaktadır:

### 1. Application Load Balancer (ALB)

**Katman**: OSI Layer 7 (Uygulama Katmanı)

**Kullanım Alanı**: HTTP/HTTPS trafiği

**Özellikler**:
- URL path-based routing (`/api/*` → API sunucuları, `/static/*` → CDN)
- Host-based routing (`api.example.com` → API, `www.example.com` → Web)
- HTTP header bazlı routing
- WebSocket ve HTTP/2 desteği
- Lambda fonksiyonlarına trafik yönlendirebilir
- Container tabanlı uygulamalar için ideal (ECS, EKS)
- Path pattern, query string, header'a göre yönlendirme

**Örnek Kullanım**:
```
http://example.com/api/users    → API Server
http://example.com/blog         → WordPress Server
http://example.com/static/*     → S3 Bucket
```

**Bu Projede Kullanım**:
- WordPress trafiğini EC2 instance'lara dağıtır
- Health check ile sağlıklı instance'ları belirler
- Auto Scaling ile dinamik instance ekleme/çıkarma

### 2. Network Load Balancer (NLB)

**Katman**: OSI Layer 4 (Transport Katmanı)

**Kullanım Alanı**: TCP/UDP trafiği

**Özellikler**:
- Çok yüksek performans (milyonlarca istek/saniye)
- Ultra-düşük latency (~100 mikrosaniye)
- Statik IP desteği
- TLS encryption desteği
- TCP, UDP, TLS protokolleri
- Extreme performance gerektiren uygulamalar için

**Örnek Kullanım**:
```
Gaming servers
IoT uygulamaları
Real-time video streaming
Financial trading applications
```

### 3. Classic Load Balancer (CLB)

**Katman**: OSI Layer 4 ve 7

**Kullanım Alanı**: Eski nesil, **KULLANIMI ÖNERİLMEZ**

**Özellikler**:
- EC2-Classic network için tasarlandı
- Basit yük dengeleme
- AWS artık yeni özellikler eklemiyor
- Legacy uygulamalar için

**Tavsiye**: Yeni projeler için ALB veya NLB kullanın!

### 4. Gateway Load Balancer (GWLB)

**Katman**: OSI Layer 3 (Network Katmanı)

**Kullanım Alanı**: 3rd-party network appliance'lar

**Özellikler**:
- Firewall, IDS/IPS, deep packet inspection
- Transparently inspect traffic
- Virtual appliance'ları scale eder

---

## Application Load Balancer (ALB) Bileşenleri

### 1. Load Balancer (ALB Instance)

Ana bileşen. Trafiği kabul edip dağıtır.

**Özellikler**:
- Multi-AZ: Birden fazla Availability Zone'da çalışır
- Managed service: AWS yönetir, siz yönetmezsiniz
- Auto-scaling: Trafik arttıkça otomatik scale olur

**Bu Projede**:
```hcl
resource "aws_lb" "wordpress" {
  name               = "wordpress-dev-alb"
  load_balancer_type = "application"
  subnets            = [subnet1, subnet2]  # Multi-AZ
  security_groups    = [sg_id]
}
```

### 2. Listener (Dinleyici)

İstekleri dinleyen ve yönlendiren bileşen.

**Özellikler**:
- Port ve Protocol tanımlı (80, 443, vs.)
- Gelen trafiği yakalayıp hangi Target Group'a göndereceğine karar verir
- Routing rules içerebilir

**Bu Projede**:
```hcl
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.wordpress.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress.arn
  }
}
```

**Listener Rules**: Farklı path'lere göre routing:
```hcl
# Örnek:
# /api/* → API Target Group
# /blog/* → Blog Target Group
# Default → Main Target Group
```

### 3. Target Group (Hedef Grup)

İsteklerin gönderildiği hedef sunucular grubu.

**Özellikler**:
- Instance, IP veya Lambda hedefleyebilir
- Health check tanımları
- Stickiness (session affinity) ayarları
- Deregistration delay

**Bu Projede**:
```hcl
resource "aws_lb_target_group" "wordpress" {
  name     = "wordpress-dev-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/health.php"
    matcher             = "200"
  }
}
```

**Target Types**:
- `instance`: EC2 Instance ID ile hedefleme
- `ip`: IP adresi ile hedefleme (container, on-prem)
- `lambda`: AWS Lambda fonksiyonu

### 4. Health Check (Sağlık Kontrolü)

Hedeflerin sağlıklı olup olmadığını kontrol eder.

**Parametreler**:
- **Interval**: Kontrol sıklığı (5-300 saniye)
- **Timeout**: Cevap bekleme süresi (2-120 saniye)
- **Healthy threshold**: Kaç başarılı check sonrası healthy (2-10)
- **Unhealthy threshold**: Kaç başarısız check sonrası unhealthy (2-10)
- **Path**: Check yapılacak URL (`/health`, `/api/status`)
- **Matcher**: Başarılı HTTP response code'u (200, 200-299)

**Bu Projede**:
```
Health Check Path: /
Interval: 30 saniye
Timeout: 5 saniye
Healthy threshold: 2
Unhealthy threshold: 2
```

**Health Check Akışı**:
```
1. ALB → http://10.0.1.100/ (Instance 1)
   → Response: 200 OK ✓ (Healthy)

2. ALB → http://10.0.1.101/ (Instance 2)
   → Response: Timeout ✗ (1. fail)

3. ALB → http://10.0.1.101/ (Instance 2) - 30 saniye sonra
   → Response: Timeout ✗ (2. fail)
   → Instance 2 UNHEALTHY olarak işaretlendi
   → ALB artık Instance 2'ye trafik göndermiyor

4. Auto Scaling → Unhealthy instance'ı terminate eder
5. Auto Scaling → Yeni instance başlatır
6. Yeni instance → Health check'leri geçiyor
7. ALB → Yeni instance'ı target group'a ekler
```

### 5. Security Groups

ALB'nin hangi trafikle erişilebilir olduğunu kontrol eder.

**Bu Projede**:
```hcl
# ALB Security Group
Inbound:
  - Port 80 (HTTP) from 0.0.0.0/0  (İnternet'ten herkes)

Outbound:
  - Port 80 to WordPress Instance Security Group
```

### 6. SSL/TLS Certificate (Opsiyonel)

HTTPS trafiği için SSL sertifikası.

**Seçenekler**:
- AWS Certificate Manager (ACM) - ÜCRETSİZ
- Imported certificate (Let's Encrypt, vs.)

**HTTPS Listener Örneği**:
```hcl
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.wordpress.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress.arn
  }
}
```

---

## Auto Scaling

### Auto Scaling Nedir?

**Auto Scaling**, uygulamanızın taleplerine göre EC2 instance sayısını otomatik olarak artırıp azaltan AWS servisidir.

### Neden Auto Scaling?

**Problem**:
- Trafik düşükken 10 sunucu çalıştırıyorsanız → Para israfı
- Trafik yüksekken 2 sunucu çalıştırıyorsanız → Uygulama yavaş/çöküyor

**Çözüm**:
- Az trafik → 1-2 instance (maliyet düşük)
- Orta trafik → 3-5 instance
- Yüksek trafik → 10+ instance (performans yüksek)

### Auto Scaling Bileşenleri

#### 1. Launch Template (Başlatma Şablonu)

Yeni instance'ların nasıl oluşturulacağını tanımlar.

**İçerik**:
- AMI ID (Amazon Machine Image)
- Instance type (t3.micro, t3.small, vs.)
- Security groups
- IAM role
- User data (başlangıç script'i)
- Storage (EBS volume)

**Bu Projede**:
```hcl
resource "aws_launch_template" "wordpress" {
  name_prefix   = "wordpress-dev"
  image_id      = data.aws_ami.amazon_linux_2.id
  instance_type = "t3.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.wordpress.name
  }

  vpc_security_group_ids = [aws_security_group.wordpress.id]

  user_data = base64encode(templatefile("user-data.sh", {
    efs_id  = aws_efs_file_system.wordpress.id
    db_host = aws_db_instance.wordpress.endpoint
  }))

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 20
      volume_type = "gp3"
      encrypted   = true
    }
  }
}
```

#### 2. Auto Scaling Group (ASG)

Instance'ları yöneten ana bileşen.

**Özellikler**:
- **Desired Capacity**: İstenen instance sayısı
- **Min Size**: Minimum instance sayısı
- **Max Size**: Maximum instance sayısı
- **Availability Zones**: Hangi AZ'lerde çalışacağı
- **Health Check Type**: EC2 veya ELB

**Bu Projede**:
```hcl
resource "aws_autoscaling_group" "wordpress" {
  name                = "wordpress-dev-asg"
  desired_capacity    = 1
  min_size            = 1
  max_size            = 4
  health_check_type   = "ELB"
  health_check_grace_period = 300

  vpc_zone_identifier = [subnet1, subnet2]
  target_group_arns   = [aws_lb_target_group.wordpress.arn]

  launch_template {
    id      = aws_launch_template.wordpress.id
    version = "$Latest"
  }
}
```

**Auto Scaling Group Lifecycle**:
```
1. ASG başlatılır (Desired: 1, Min: 1, Max: 4)
2. 1 instance launch edilir (user-data çalışır)
3. Instance InService olur
4. ALB health check başlar
5. Health check pass → Instance Healthy
6. ALB trafiği instance'a gönderir

--- Trafik Artışı ---

7. CloudWatch Alarm → CPU > 50%
8. Scaling Policy tetiklenir
9. Desired Capacity: 1 → 2
10. Yeni instance launch edilir
11. Yeni instance Healthy olur
12. ALB her iki instance'a trafik dağıtır

--- Trafik Azalışı ---

13. CloudWatch Alarm → CPU < 20%
14. Scaling Policy tetiklenir
15. Desired Capacity: 2 → 1
16. Bir instance terminate edilir
```

#### 3. Scaling Policies (Ölçeklendirme Politikaları)

Instance sayısını ne zaman artırıp azaltacağını belirler.

**Policy Türleri**:

##### a) Target Tracking Scaling
Belirli bir metriği hedef değerde tutmaya çalışır.

```hcl
# Örnek: CPU'yu %50'de tut
resource "aws_autoscaling_policy" "target_tracking" {
  name                   = "cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.wordpress.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50.0
  }
}
```

##### b) Step Scaling
Metrik değerine göre farklı miktarda scale eder.

```hcl
# CPU %50-70 → +1 instance
# CPU %70-90 → +2 instance
# CPU >90    → +3 instance
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "step-scale-up"
  autoscaling_group_name = aws_autoscaling_group.wordpress.name
  policy_type            = "StepScaling"
  adjustment_type        = "ChangeInCapacity"

  step_adjustment {
    scaling_adjustment          = 1
    metric_interval_lower_bound = 0
    metric_interval_upper_bound = 20
  }

  step_adjustment {
    scaling_adjustment          = 2
    metric_interval_lower_bound = 20
    metric_interval_upper_bound = 40
  }

  step_adjustment {
    scaling_adjustment          = 3
    metric_interval_lower_bound = 40
  }
}
```

##### c) Simple Scaling
Tek bir değer ile scale eder.

```hcl
# CPU > 50% → +1 instance
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "simple-scale-up"
  autoscaling_group_name = aws_autoscaling_group.wordpress.name
  policy_type            = "SimpleScaling"
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 300
}
```

**Bu Projede**:
```hcl
# Scale UP: CPU > 50% için 2 datapoint (10 dakika)
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "wordpress-dev-scale-up"
  autoscaling_group_name = aws_autoscaling_group.wordpress.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 300
}

# Scale DOWN: CPU < 20% için 2 datapoint (10 dakika)
resource "aws_autoscaling_policy" "scale_down" {
  name                   = "wordpress-dev-scale-down"
  autoscaling_group_name = aws_autoscaling_group.wordpress.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 300
}
```

#### 4. CloudWatch Alarms (İzleme ve Tetikleyici)

Scaling policy'leri tetikleyen alarmlar.

**Bu Projede**:
```hcl
# HIGH CPU ALARM
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "wordpress-dev-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 50

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.wordpress.name
  }

  alarm_actions = [
    aws_autoscaling_policy.scale_up.arn,
    aws_sns_topic.alarms.arn
  ]
}
```

**Alarm Mantığı**:
```
evaluation_periods = 2
period = 300 (5 dakika)

→ 5 dakikada bir CPU kontrolü
→ 2 ardışık kontrol threshold'u aşarsa alarm

Örnek:
T+0:  CPU 40% → OK
T+5:  CPU 60% → 1. datapoint ALARM
T+10: CPU 55% → 2. datapoint ALARM → ALARM TETİKLENDİ!
```

---

## Elastic File System (EFS)

### EFS Nedir?

**EFS (Elastic File System)**, AWS'nin yönetilen, scalable, elastic NFS (Network File System) servisidir.

### EFS vs EBS

| Özellik | EBS | EFS |
|---------|-----|-----|
| **Bağlantı** | Tek instance | Binlerce instance aynı anda |
| **Availability** | Tek AZ | Multi-AZ |
| **Performans** | Sabit (provisioned IOPS) | Bursting + Provisioned |
| **Fiyat** | GB başına düşük | GB başına yüksek |
| **Kullanım** | Boot volume, database | Shared storage, content |
| **Resize** | Manuel | Otomatik |

### EFS Kullanım Senaryoları

1. **Web Sunucuları**: Aynı dosyaları paylaşan birden fazla web server
2. **Content Management**: WordPress, Drupal gibi CMS'ler
3. **Shared Development**: Ekip içinde dosya paylaşımı
4. **Machine Learning**: Ortak dataset'ler
5. **Container Storage**: Docker, Kubernetes persistent volume

### EFS Bileşenleri

#### 1. File System

Ana EFS kaynağı.

**Bu Projede**:
```hcl
resource "aws_efs_file_system" "wordpress" {
  creation_token = "wordpress-dev-efs"
  encrypted      = true

  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name = "wordpress-dev-efs"
  }
}
```

**Performance Modes**:
- **General Purpose**: Web server, CMS (varsayılan)
- **Max I/O**: Big data, media processing

**Throughput Modes**:
- **Bursting**: Otomatik scaling (küçük-orta iş yükleri)
- **Provisioned**: Sabit throughput (büyük iş yükleri)

#### 2. Mount Targets

Her Availability Zone'da EFS'e erişim noktası.

**Bu Projede**:
```hcl
resource "aws_efs_mount_target" "wordpress" {
  count           = 2
  file_system_id  = aws_efs_file_system.wordpress.id
  subnet_id       = element(private_subnets, count.index)
  security_groups = [aws_security_group.efs.id]
}
```

**Mimari**:
```
AZ 1 (us-east-1a):
  - Private Subnet 1
  - EFS Mount Target 1
  - EC2 Instances → NFS mount → Mount Target 1 → EFS

AZ 2 (us-east-1b):
  - Private Subnet 2
  - EFS Mount Target 2
  - EC2 Instances → NFS mount → Mount Target 2 → EFS
```

#### 3. Security Groups

NFS trafiği (Port 2049) için güvenlik kuralları.

**Bu Projede**:
```hcl
resource "aws_security_group" "efs" {
  name   = "wordpress-dev-efs-sg"
  vpc_id = vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress.id]
    description     = "NFS from WordPress instances"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

### EFS'i Instance'a Mount Etme

**User Data Script'inde**:
```bash
#!/bin/bash

# EFS utilities kur
yum install -y amazon-efs-utils

# EFS mount point oluştur
mkdir -p /var/www/html

# EFS'i mount et
mount -t efs -o tls fs-12345678:/ /var/www/html

# Otomatik mount için /etc/fstab
echo "fs-12345678:/ /var/www/html efs _netdev,tls 0 0" >> /etc/fstab
```

**Bu Projede**:
```bash
# WordPress dosyaları EFS'de saklanır
/var/www/html/wp-content/uploads/  → EFS
/var/www/html/wp-content/plugins/  → EFS
/var/www/html/wp-content/themes/   → EFS

# Tüm instance'lar aynı dosyaları görür
Instance 1: /var/www/html → EFS
Instance 2: /var/www/html → EFS
Instance 3: /var/www/html → EFS
```

### EFS Lifecycle Management

Erişilmeyen dosyaları ucuz storage'a taşıma.

**Storage Classes**:
- **Standard**: Sık erişilen dosyalar (pahalı)
- **Infrequent Access (IA)**: Nadir erişilen dosyalar (ucuz)

**Bu Projede**:
```hcl
lifecycle_policy {
  transition_to_ia = "AFTER_30_DAYS"
}
```

**Mantık**:
```
30 gün erişilmeyen dosya:
  Standard ($0.30/GB/month)
  ↓
  Infrequent Access ($0.025/GB/month)

Tasarruf: %92!
```

---

## Diğer Bileşenler

### 1. VPC (Virtual Private Cloud)

Kendi özel ağınız.

**Bu Projede**:
- **CIDR**: 10.0.0.0/16 (65,536 IP adresi)
- **Public Subnet**: 10.0.1.0/24, 10.0.2.0/24 (ALB için)
- **Private Subnet**: 10.0.11.0/24, 10.0.12.0/24 (WordPress için)
- **Database Subnet**: 10.0.21.0/24, 10.0.22.0/24 (RDS için)

### 2. Internet Gateway (IGW)

VPC'den internete çıkış.

**Kullanım**:
```
Public Subnet → Internet Gateway → Internet
```

### 3. NAT Gateway

Private subnet'ten internete çıkış (tek yönlü).

**Kullanım**:
```
Private Subnet → NAT Gateway (Public Subnet'te) → Internet Gateway → Internet
```

**Bu Projede**:
```
WordPress Instance (Private) → yum update (İnternet'e çıkış gerekli)
  → NAT Gateway → Internet
```

### 4. RDS (Relational Database Service)

Yönetilen MySQL/PostgreSQL/MariaDB servisi.

**Bu Projede**:
```hcl
resource "aws_db_instance" "wordpress" {
  identifier          = "wordpress-dev-mysql"
  engine              = "mysql"
  engine_version      = "8.0"
  instance_class      = "db.t3.micro"
  allocated_storage   = 20
  storage_encrypted   = true

  db_name  = "wordpress_db"
  username = "admin"
  password = var.db_password

  multi_az               = false  # Prod'da true
  publicly_accessible    = false
  skip_final_snapshot    = true

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.wordpress.name
}
```

**Özellikler**:
- Otomatik backup
- Otomatik patch
- Read replica
- Multi-AZ failover
- Encryption at rest

### 5. CloudWatch

İzleme ve loglama servisi.

**Kullanım Alanları**:
- CPU, Memory, Disk metrikler
- Custom metrikler
- Alarmlar
- Log aggregation
- Dashboard'lar

**Bu Projede**:
```
CloudWatch Metrics:
  - ASG → CPUUtilization
  - ALB → RequestCount, TargetResponseTime
  - RDS → DatabaseConnections, CPUUtilization

CloudWatch Alarms:
  - CPU > 50% → Scale Up
  - CPU < 20% → Scale Down

CloudWatch Logs:
  - /var/log/httpd/access_log → CloudWatch Logs
  - /var/log/httpd/error_log → CloudWatch Logs
```

### 6. SNS (Simple Notification Service)

Bildirim servisi.

**Bu Projede**:
```hcl
resource "aws_sns_topic" "alarms" {
  name = "wordpress-dev-alarms"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = "your-email@example.com"
}
```

**Bildirimler**:
```
CPU High → SNS → Email
CPU Low → SNS → Email
Instance Unhealthy → SNS → Email
```

### 7. IAM (Identity and Access Management)

Instance'lara AWS servislerine erişim izni.

**Bu Projede**:
```hcl
# WordPress instance'ları CloudWatch'a log gönderebilsin
resource "aws_iam_role" "wordpress" {
  name = "wordpress-dev-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.wordpress.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}
```

---

## Proje Mimarisinin Tam Akışı

### 1. Kullanıcı İsteği

```
Kullanıcı → http://wordpress-dev-alb-123456.us-east-1.elb.amazonaws.com
```

### 2. DNS Resolution

```
Domain → Route 53 (opsiyonel) → ALB DNS
```

### 3. Application Load Balancer

```
ALB (Public Subnet):
  - Security Group: 80 portunu kabul et
  - Listener: Port 80 HTTP
  - Target Group: wordpress-dev-tg
  - Health Check: / yolunu kontrol et
```

### 4. Target Group Selection

```
ALB:
  - Target Group içinde 2 healthy instance var
  - Round-robin algoritması ile seç
  - Instance 1'i seç (10.0.11.100)
```

### 5. WordPress Instance

```
EC2 Instance (Private Subnet):
  - Security Group: ALB'den 80 port
  - Apache/PHP çalışıyor
  - /var/www/html → EFS mount
  - WordPress dosyaları EFS'de
```

### 6. Database Query

```
WordPress:
  - MySQL connection → RDS endpoint
  - Security Group: WordPress'den 3306 port
  - Query: SELECT * FROM wp_posts
```

### 7. File Access

```
WordPress:
  - Uploaded image → /var/www/html/wp-content/uploads/
  - EFS mount → tüm instance'lar aynı dosyayı görür
```

### 8. Response

```
WordPress → HTML oluştur
  → Apache → HTTP Response
  → ALB
  → Kullanıcı
```

### 9. Auto Scaling (Trafik Artışı)

```
1. Çok fazla istek geldi
2. Instance CPU %80'e çıktı
3. CloudWatch: CPU > 50% (2 datapoint)
4. Alarm: ALARM state
5. Auto Scaling Policy: +1 instance
6. ASG: Desired 1 → 2
7. Launch Template kullanılarak yeni instance başlatıldı
8. User data çalıştı (Apache, PHP, WordPress, EFS mount)
9. Instance InService
10. Health check başarılı
11. ALB: Instance 2'yi target group'a ekledi
12. Trafik artık 2 instance'a dağıtılıyor
```

---

## Maliyet Optimizasyonu

### 1. Auto Scaling

```
Sabit 3 instance (7/24):
  3 × $7/ay (t3.micro) = $21/ay

Auto Scaling (1-3 instance):
  - Gece: 1 instance
  - Gündüz: 2 instance
  - Peak: 3 instance
  Ortalama: ~1.5 instance = $10.5/ay

Tasarruf: %50
```

### 2. EFS Lifecycle

```
100 GB WordPress uploads:
  - Standard: 100 GB × $0.30 = $30/ay
  - IA (80 GB nadir erişilen): 80 GB × $0.025 = $2/ay
  - Standard (20 GB sık erişilen): 20 GB × $0.30 = $6/ay
  Toplam: $8/ay

Tasarruf: %73
```

### 3. RDS Snapshot Yerine Backup

```
RDS Multi-AZ: $30/ay
RDS Single-AZ + Snapshots: $15/ay + $2/ay = $17/ay

Tasarruf: %43 (Dev ortamı için)
```

---

## Güvenlik En İyi Pratikleri

### 1. Security Groups

```
ALB Security Group:
  Inbound: 80, 443 from 0.0.0.0/0
  Outbound: 80 to WordPress SG

WordPress Security Group:
  Inbound: 80 from ALB SG
  Inbound: 22 from Bastion SG
  Outbound: 3306 to RDS SG
  Outbound: 2049 to EFS SG

RDS Security Group:
  Inbound: 3306 from WordPress SG
  Outbound: NONE

EFS Security Group:
  Inbound: 2049 from WordPress SG
  Outbound: NONE
```

### 2. Private Subnets

```
WordPress Instance:
  - Public IP: YOK
  - Private IP: 10.0.11.100
  - İnternet erişimi: NAT Gateway üzerinden
  - SSH: Bastion Host üzerinden
```

### 3. Encryption

```
RDS: Encryption at rest (AES-256)
EBS: Encrypted volumes
EFS: Encrypted file system
ALB: HTTPS (TLS 1.2+)
```

---

## Kaynaklar

### AWS Dokümantasyonu

- [Elastic Load Balancing](https://docs.aws.amazon.com/elasticloadbalancing/)
- [Auto Scaling](https://docs.aws.amazon.com/autoscaling/)
- [Amazon EFS](https://docs.aws.amazon.com/efs/)
- [Amazon VPC](https://docs.aws.amazon.com/vpc/)
- [Amazon RDS](https://docs.aws.amazon.com/rds/)

### Bu Proje

- [README.md](README.md) - Ana dokümantasyon
- [PERFORMANS_TESTI.md](PERFORMANS_TESTI.md) - Auto Scaling test kılavuzu
- [MANUAL_TESTS.md](MANUAL_TESTS.md) - Manuel test senaryoları

---

**Bu dokümanda öğrendikleriniz**:

✅ ELB nedir ve türleri (ALB, NLB, CLB, GWLB)
✅ ALB bileşenleri (Listener, Target Group, Health Check)
✅ Auto Scaling nasıl çalışır (ASG, Launch Template, Scaling Policies)
✅ EFS nedir ve EBS'den farkları
✅ CloudWatch Alarms ile izleme
✅ AWS mimarisinde güvenlik
✅ Maliyet optimizasyonu stratejileri

**Sıradaki Adımlar**:

1. [README.md](README.md) okuyun
2. Terraform ile deploy edin
3. [PERFORMANS_TESTI.md](PERFORMANS_TESTI.md) ile Auto Scaling test edin
4. Production için önerileri uygulayın

---

Son güncelleme: 2025-01-19
