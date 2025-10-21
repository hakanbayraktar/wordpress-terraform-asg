# Manuel Test Talimatları

Bu dokümanda, deploy edilen WordPress Auto Scaling altyapısının tüm bileşenlerini **manuel olarak** test etmek için gereken komutlar ve talimatlar bulunmaktadır.

> **Not:** Otomatik test için `./scripts/run-tests.sh` scriptini kullanabilirsiniz. Bu dokümandaki testler, scriptsiz manuel test yapmak isteyenler içindir.

## 📋 İçindekiler

1. [Ön Hazırlık](#-ön-hazırlık)
2. [Test 1: WordPress Web Erişimi](#test-1-wordpress-web-erişimi)
3. [Test 2: VPN Server Bağlantısı](#test-2-vpn-server-bağlantısı)
4. [Test 3: Bastion Host Erişimi](#test-3-bastion-host-erişimi)
5. [Test 4: Auto Scaling Group Durumu](#test-4-auto-scaling-group-durumu)
6. [Test 5: CloudWatch Alarmları](#test-5-cloudwatch-alarmları)
7. [Test 6: RDS MySQL Bağlantısı](#test-6-rds-mysql-bağlantısı)
8. [Test 7: EFS File System](#test-7-efs-file-system)
9. [Test 8: Load Balancer Health](#test-8-load-balancer-health)
10. [Test 9: Security Groups](#test-9-security-groups)
11. [Test 10: SNS Email Subscription](#test-10-sns-email-subscription)
12. [Yük Testi: Auto Scaling](#yük-testi-auto-scaling)

---

## 🔧 Ön Hazırlık

### 1. Terraform Outputs Değerlerini Al

Öncelikle tüm erişim bilgilerini almak için:

```bash
# WordPress URL
WORDPRESS_URL=$(terraform output -raw wordpress_url)
echo "WordPress URL: $WORDPRESS_URL"

# Bastion IP
BASTION_IP=$(terraform output -raw bastion_public_ip)
echo "Bastion IP: $BASTION_IP"

# VPN Server IP
VPN_SERVER_IP=$(terraform output -raw vpn_server_ip)
echo "VPN Server IP: $VPN_SERVER_IP"

# VPN Kullanıcı Adı
VPN_USER=$(terraform output -raw vpn_user)
echo "VPN User: $VPN_USER"

# RDS Endpoint
RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
echo "RDS Endpoint: $RDS_ENDPOINT"

# ASG Name
ASG_NAME=$(terraform output -raw autoscaling_group_name)
echo "ASG Name: $ASG_NAME"

# EFS ID
EFS_ID=$(terraform output -raw efs_id)
echo "EFS ID: $EFS_ID"

# SNS Topic ARN
SNS_TOPIC=$(terraform output -raw sns_topic_arn)
echo "SNS Topic: $SNS_TOPIC"

# VPC ID
VPC_ID=$(terraform output -raw vpc_id)
echo "VPC ID: $VPC_ID"

# ALB DNS Name
ALB_DNS=$(terraform output -raw alb_dns_name)
echo "ALB DNS: $ALB_DNS"
```

### 2. Terraform Variables Değerlerini Al

```bash
# AWS Region
REGION=$(grep 'aws_region' terraform.dev.tfvars | cut -d'"' -f2)
echo "Region: $REGION"

# DB Password (gerekirse)
DB_PASSWORD=$(grep 'db_password' terraform.dev.tfvars | cut -d'"' -f2)
```

---

## Test 1: WordPress Web Erişimi

### Amaç
WordPress web sitesinin ALB üzerinden erişilebilir olduğunu doğrulamak.

### Komutlar

#### 1.1 HTTP Status Code Kontrolü
```bash
# HTTP 200 veya 302 dönmeli (başarılı)
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" $WORDPRESS_URL
```

**Beklenen Sonuç:** `HTTP Status: 200` veya `HTTP Status: 302`

#### 1.2 Detaylı Response Kontrolü
```bash
# Response headers ve timing
curl -I -w "\nTime Total: %{time_total}s\n" $WORDPRESS_URL
```

#### 1.3 Tarayıcıdan Test
```bash
# URL'yi clipboard'a kopyala
echo $WORDPRESS_URL | pbcopy  # macOS
# veya
echo $WORDPRESS_URL | xclip -selection clipboard  # Linux

# Sonra tarayıcıda aç
open $WORDPRESS_URL  # macOS
# veya
xdg-open $WORDPRESS_URL  # Linux
```

### Sorun Giderme
- ❌ **Connection timeout:** ALB security group veya target health kontrol et
- ❌ **HTTP 503:** Target'lar unhealthy olabilir, ASG instance'larını kontrol et
- ❌ **HTTP 502:** WordPress instance'ları başlatma aşamasında olabilir

---

## Test 2: VPN Server Bağlantısı

### Amaç
OpenVPN server'ın çalıştığını ve erişilebilir olduğunu doğrulamak.

### Komutlar

#### 2.1 SSH Port Kontrolü (22)
```bash
# Port 22 açık mı?
timeout 5 bash -c "echo > /dev/tcp/$VPN_SERVER_IP/22" && echo "✓ SSH Port AÇIK" || echo "✗ SSH Port KAPALI"
```

**Beklenen Sonuç:** `✓ SSH Port AÇIK`

#### 2.2 OpenVPN Port Kontrolü (1194/UDP)
```bash
# UDP port taraması (nc veya nmap gerekli)
nc -vuz -w 3 $VPN_SERVER_IP 1194

# veya nmap ile
nmap -sU -p 1194 $VPN_SERVER_IP
```

**Beklenen Sonuç:** Port açık ve OpenVPN servisi yanıt veriyor

#### 2.3 VPN Config Dosyası Kontrolü
```bash
# .ovpn dosyası oluşturuldu mu?
ssh -i ~/.ssh/wordpress-key.pem \
    -o StrictHostKeyChecking=no \
    ubuntu@$VPN_SERVER_IP \
    "ls -lh /home/ubuntu/${VPN_USER}.ovpn"
```

**Beklenen Sonuç:** Dosya mevcut ve ~5KB boyutunda

#### 2.4 VPN Config Dosyasını İndir
```bash
# Lokal makineye indir
mkdir -p ~/.vpn
scp -i ~/.ssh/wordpress-key.pem \
    -o StrictHostKeyChecking=no \
    ubuntu@$VPN_SERVER_IP:/home/ubuntu/${VPN_USER}.ovpn \
    ~/.vpn/${VPN_USER}.ovpn

# İçeriğini kontrol et
cat ~/.vpn/${VPN_USER}.ovpn | head -20
```

#### 2.5 OpenVPN Servis Durumu
```bash
# VPN server'da servis çalışıyor mu?
ssh -i ~/.ssh/wordpress-key.pem ubuntu@$VPN_SERVER_IP \
    "sudo systemctl status openvpn-server@server.service"
```

**Beklenen Sonuç:** `Active: active (running)`

### VPN Bağlantısı Testi

#### macOS
```bash
# Tunnelblick kullanarak
open ~/.vpn/${VPN_USER}.ovpn

# veya OpenVPN CLI
sudo openvpn --config ~/.vpn/${VPN_USER}.ovpn
```

#### Linux
```bash
# OpenVPN CLI
sudo openvpn --config ~/.vpn/${VPN_USER}.ovpn
```

#### Bağlantı Sonrası Kontrol
```bash
# VPN IP'sini kontrol et (10.8.0.x olmalı)
ip addr show tun0  # Linux
ifconfig utun0     # macOS

# VPN üzerinden private IP'lere erişim testi
ping 10.0.11.10  # Herhangi bir private IP
```

---

## Test 3: Bastion Host Erişimi

### Amaç
Bastion host üzerinden private instance'lara SSH erişimi testi.

### Komutlar

#### 3.1 Bastion'a Direkt SSH
```bash
# Bastion'a bağlan
ssh -i ~/.ssh/wordpress-key.pem ec2-user@$BASTION_IP

# Bağlandıktan sonra
whoami  # ec2-user
hostname  # bastion hostname
exit
```

#### 3.2 WordPress Instance IP'lerini Bul
```bash
# ASG'deki tüm instance'ların private IP'lerini listele
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names $ASG_NAME \
    --region $REGION \
    --query 'AutoScalingGroups[0].Instances[*].InstanceId' \
    --output text | xargs -I {} aws ec2 describe-instances \
    --instance-ids {} \
    --region $REGION \
    --query 'Reservations[0].Instances[0].[PrivateIpAddress,State.Name]' \
    --output text
```

#### 3.3 ProxyCommand ile WordPress Instance'a Erişim
```bash
# İlk instance IP'sini al
WP_INSTANCE_IP=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names $ASG_NAME \
    --region $REGION \
    --query 'AutoScalingGroups[0].Instances[0].InstanceId' \
    --output text | xargs aws ec2 describe-instances \
    --instance-ids {} \
    --region $REGION \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text)

echo "WordPress Instance IP: $WP_INSTANCE_IP"

# ProxyCommand ile bağlan
ssh -i ~/.ssh/wordpress-key.pem \
    -o ProxyCommand="ssh -W %h:%p -i ~/.ssh/wordpress-key.pem ec2-user@$BASTION_IP" \
    ec2-user@$WP_INSTANCE_IP

# Bağlandıktan sonra test komutları
whoami                    # ec2-user
hostname                  # wordpress instance hostname
df -h | grep efs          # EFS mount kontrolü
systemctl status php-fpm  # PHP-FPM çalışıyor mu
systemctl status nginx    # Nginx çalışıyor mu
curl localhost            # Local WordPress erişimi
exit
```

#### 3.4 SSH Config ile Kalıcı Ayar
```bash
# ~/.ssh/config dosyasına ekle
cat >> ~/.ssh/config << EOF

# WordPress Bastion Host
Host wordpress-bastion
    HostName $BASTION_IP
    User ec2-user
    IdentityFile ~/.ssh/wordpress-key.pem
    StrictHostKeyChecking no

# WordPress Private Instances
Host wordpress-private-*
    User ec2-user
    IdentityFile ~/.ssh/wordpress-key.pem
    ProxyCommand ssh -W %h:%p wordpress-bastion
    StrictHostKeyChecking no
EOF

# Artık kısa komutla bağlanabilirsiniz
ssh wordpress-bastion
ssh wordpress-private-$WP_INSTANCE_IP
```

---

## Test 4: Auto Scaling Group Durumu

### Amaç
ASG'nin doğru yapılandırıldığını ve instance'ların çalıştığını doğrulamak.

### Komutlar

#### 4.1 ASG Genel Durumu
```bash
# Kapsamlı bilgi
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names $ASG_NAME \
    --region $REGION \
    --output table
```

#### 4.2 Özet Bilgi
```bash
# Sadece önemli değerler
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names $ASG_NAME \
    --region $REGION \
    --query 'AutoScalingGroups[0].{
        MinSize:MinSize,
        MaxSize:MaxSize,
        Desired:DesiredCapacity,
        Current:length(Instances),
        HealthCheck:HealthCheckType,
        Instances:Instances[*].[InstanceId,HealthStatus,LifecycleState]
    }' \
    --output table
```

**Beklenen Sonuç:**
- MinSize: 1
- MaxSize: 2-4 (dev ortamı için)
- Desired: 1 (veya scale out olduysa daha fazla)
- Current: Desired ile aynı olmalı
- HealthStatus: Healthy
- LifecycleState: InService

#### 4.3 Instance Health Durumu
```bash
# Tüm instance'ların health check sonuçları
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names $ASG_NAME \
    --region $REGION \
    --query 'AutoScalingGroups[0].Instances[*].[InstanceId,HealthStatus,LifecycleState]' \
    --output table
```

#### 4.4 Scaling Policies
```bash
# Scale up ve scale down policy'leri
aws autoscaling describe-policies \
    --auto-scaling-group-name $ASG_NAME \
    --region $REGION \
    --output table
```

#### 4.5 Scaling Activities (Son Aktiviteler)
```bash
# Son scaling aktiviteleri (son 24 saat)
aws autoscaling describe-scaling-activities \
    --auto-scaling-group-name $ASG_NAME \
    --region $REGION \
    --max-records 10 \
    --query 'Activities[*].[StartTime,StatusCode,Description]' \
    --output table
```

#### 4.6 Canlı İzleme
```bash
# Her 10 saniyede bir ASG durumunu göster
watch -n 10 "aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names $ASG_NAME \
    --region $REGION \
    --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Current:length(Instances)}'"
```

---

## Test 5: CloudWatch Alarmları

### Amaç
CloudWatch alarmlarının doğru yapılandırıldığını ve çalıştığını kontrol etmek.

### Komutlar

#### 5.1 Tüm Alarmları Listele
```bash
# wordpress-dev prefix'i ile başlayan tüm alarmlar
aws cloudwatch describe-alarms \
    --alarm-name-prefix "wordpress-dev" \
    --region $REGION \
    --output table
```

#### 5.2 Alarm Durumları (Özet)
```bash
# Sadece alarm isimleri ve durumları
aws cloudwatch describe-alarms \
    --alarm-name-prefix "wordpress-dev" \
    --region $REGION \
    --query 'MetricAlarms[*].[AlarmName,StateValue,StateReason]' \
    --output table
```

**Beklenen Alarm Durumları:**
- `wordpress-dev-cpu-high`: OK (CPU < 50%)
- `wordpress-dev-cpu-low`: OK (CPU > 30%)
- `wordpress-dev-unhealthy-hosts`: OK (Unhealthy count = 0)

#### 5.3 Belirli Bir Alarm Detayı
```bash
# CPU High alarm detayları
aws cloudwatch describe-alarms \
    --alarm-names "wordpress-dev-cpu-high" \
    --region $REGION \
    --output json | jq -r '.MetricAlarms[0] | {
        Name:.AlarmName,
        State:.StateValue,
        Threshold:.Threshold,
        Period:.Period,
        EvaluationPeriods:.EvaluationPeriods,
        DatapointsToAlarm:.DatapointsToAlarm,
        LastStateChange:.StateUpdatedTimestamp
    }'
```

#### 5.4 Alarm Geçmişi
```bash
# Son 24 saatteki alarm state değişiklikleri
aws cloudwatch describe-alarm-history \
    --alarm-name "wordpress-dev-cpu-high" \
    --region $REGION \
    --history-item-type StateUpdate \
    --max-records 10 \
    --query 'AlarmHistoryItems[*].[Timestamp,HistorySummary]' \
    --output table
```

#### 5.5 Canlı Alarm İzleme
```bash
# Her 30 saniyede bir tüm alarm durumlarını göster
watch -n 30 "aws cloudwatch describe-alarms \
    --alarm-name-prefix 'wordpress-dev' \
    --region $REGION \
    --query 'MetricAlarms[*].[AlarmName,StateValue]' \
    --output table"
```

#### 5.6 CloudWatch Metrics (CPU Kullanımı)
```bash
# ASG'deki tüm instance'ların CPU metriklerini al (son 1 saat)
aws cloudwatch get-metric-statistics \
    --namespace AWS/EC2 \
    --metric-name CPUUtilization \
    --dimensions Name=AutoScalingGroupName,Value=$ASG_NAME \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average \
    --region $REGION \
    --query 'Datapoints | sort_by(@, &Timestamp)[*].[Timestamp,Average]' \
    --output table
```

---

## Test 6: RDS MySQL Bağlantısı

### Amaç
RDS instance'ın erişilebilir ve çalışır durumda olduğunu doğrulamak.

### Komutlar

#### 6.1 RDS Instance Durumu
```bash
# RDS instance bilgileri
aws rds describe-db-instances \
    --region $REGION \
    --query "DBInstances[?contains(DBInstanceIdentifier, 'wordpress')].[
        DBInstanceIdentifier,
        DBInstanceStatus,
        Engine,
        EngineVersion,
        Endpoint.Address,
        Endpoint.Port,
        MultiAZ,
        StorageType,
        AllocatedStorage
    ]" \
    --output table
```

**Beklenen Sonuç:** Status = `available`

#### 6.2 Port Erişilebilirlik Testi (Bastion Üzerinden)
```bash
# Bastion üzerinden RDS port kontrolü
ssh -i ~/.ssh/wordpress-key.pem ec2-user@$BASTION_IP \
    "timeout 5 bash -c '</dev/tcp/$RDS_ENDPOINT/3306' && echo '✓ RDS Port AÇIK' || echo '✗ RDS Port KAPALI'"
```

**Beklenen Sonuç:** `✓ RDS Port AÇIK`

#### 6.3 SSH Tunnel ile RDS Bağlantısı

##### Terminal 1: Tunnel Oluştur
```bash
# Local 3307 portundan RDS'ye tunnel
ssh -i ~/.ssh/wordpress-key.pem \
    -L 3307:$RDS_ENDPOINT:3306 \
    -N ec2-user@$BASTION_IP
```

##### Terminal 2: MySQL Bağlantısı
```bash
# Local MySQL client ile bağlan
mysql -h 127.0.0.1 -P 3307 -u admin -p

# Şifre: terraform.dev.tfvars içindeki db_password
```

##### MySQL Komutları (Bağlandıktan sonra)
```sql
-- Veritabanlarını listele
SHOW DATABASES;

-- WordPress veritabanını seç
USE wordpress;

-- Tabloları listele
SHOW TABLES;

-- Tablo boyutlarını göster
SELECT
    table_name AS 'Table',
    ROUND(((data_length + index_length) / 1024 / 1024), 2) AS 'Size (MB)'
FROM information_schema.TABLES
WHERE table_schema = 'wordpress'
ORDER BY (data_length + index_length) DESC;

-- WordPress kullanıcılarını listele
SELECT user_login, user_email FROM wp_users;

-- Çıkış
EXIT;
```

#### 6.4 Docker ile MySQL Client (Alternatif)
```bash
# MySQL 8.0 client ile bağlan (local MySQL 9.x uyumsuzluk sorununu çözer)
docker run -it --rm mysql:8.0 mysql \
    -h host.docker.internal \
    -P 3307 \
    -u admin \
    -p
```

#### 6.5 Bastion Üzerinden MySQL Client
```bash
# Bastion'a bağlan ve MySQL client kur
ssh -i ~/.ssh/wordpress-key.pem ec2-user@$BASTION_IP

# MySQL client kur (Bastion üzerinde)
sudo dnf install -y mysql

# RDS'ye bağlan
mysql -h $RDS_ENDPOINT -P 3306 -u admin -p

# Test sorguları
SHOW DATABASES;
USE wordpress;
SHOW TABLES;
EXIT;

# Bastion'dan çık
exit
```

#### 6.6 RDS Backup ve Snapshot Kontrolü
```bash
# Otomatik backup ayarları
aws rds describe-db-instances \
    --region $REGION \
    --query "DBInstances[?contains(DBInstanceIdentifier, 'wordpress')].[
        DBInstanceIdentifier,
        BackupRetentionPeriod,
        PreferredBackupWindow,
        PreferredMaintenanceWindow
    ]" \
    --output table

# Mevcut snapshot'lar
aws rds describe-db-snapshots \
    --region $REGION \
    --query "DBSnapshots[?contains(DBInstanceIdentifier, 'wordpress')].[
        DBSnapshotIdentifier,
        SnapshotCreateTime,
        Status,
        AllocatedStorage
    ]" \
    --output table
```

---

## Test 7: EFS File System

### Amaç
EFS file system'in oluşturulduğunu ve WordPress instance'larına mount edildiğini doğrulamak.

### Komutlar

#### 7.1 EFS Durumu
```bash
# EFS file system bilgileri
aws efs describe-file-systems \
    --file-system-id $EFS_ID \
    --region $REGION \
    --query 'FileSystems[0].[FileSystemId,LifeCycleState,SizeInBytes.Value,NumberOfMountTargets]' \
    --output table
```

**Beklenen Sonuç:** LifeCycleState = `available`

#### 7.2 EFS Mount Targets
```bash
# Mount target'ları listele (her AZ'de bir tane olmalı)
aws efs describe-mount-targets \
    --file-system-id $EFS_ID \
    --region $REGION \
    --query 'MountTargets[*].[MountTargetId,AvailabilityZoneName,IpAddress,LifeCycleState]' \
    --output table
```

#### 7.3 WordPress Instance'da EFS Mount Kontrolü
```bash
# İlk WordPress instance'a bağlan
WP_INSTANCE_IP=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names $ASG_NAME \
    --region $REGION \
    --query 'AutoScalingGroups[0].Instances[0].InstanceId' \
    --output text | xargs aws ec2 describe-instances \
    --instance-ids {} \
    --region $REGION \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text)

# SSH ile bağlan ve mount kontrolü
ssh -i ~/.ssh/wordpress-key.pem \
    -o ProxyCommand="ssh -W %h:%p -i ~/.ssh/wordpress-key.pem ec2-user@$BASTION_IP" \
    ec2-user@$WP_INSTANCE_IP \
    "df -h | grep efs && echo '---' && mount | grep efs"
```

**Beklenen Çıktı:**
```
127.0.0.1:/     XX GB  XX GB  XX GB  X% /var/www/html/wp-content
---
127.0.0.1:/ on /var/www/html/wp-content type nfs4 ...
```

#### 7.4 EFS İçeriğini Kontrol Et
```bash
# WordPress uploads dizinini listele
ssh -i ~/.ssh/wordpress-key.pem \
    -o ProxyCommand="ssh -W %h:%p -i ~/.ssh/wordpress-key.pem ec2-user@$BASTION_IP" \
    ec2-user@$WP_INSTANCE_IP \
    "sudo ls -lah /var/www/html/wp-content/uploads/"
```

#### 7.5 EFS Performans Metrikleri
```bash
# EFS throughput metrikleri (son 1 saat)
aws cloudwatch get-metric-statistics \
    --namespace AWS/EFS \
    --metric-name DataReadIOBytes \
    --dimensions Name=FileSystemId,Value=$EFS_ID \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 3600 \
    --statistics Sum \
    --region $REGION \
    --output table
```

---

## Test 8: Load Balancer Health

### Amaç
Application Load Balancer'ın sağlıklı çalıştığını ve target'ların healthy olduğunu doğrulamak.

### Komutlar

#### 8.1 ALB Bilgileri
```bash
# ALB detayları
aws elbv2 describe-load-balancers \
    --region $REGION \
    --query "LoadBalancers[?contains(LoadBalancerName, 'wordpress')].[
        LoadBalancerName,
        State.Code,
        Type,
        Scheme,
        DNSName
    ]" \
    --output table
```

#### 8.2 Target Group Durumu
```bash
# Target group'u bul
TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups \
    --region $REGION \
    --query "TargetGroups[?contains(TargetGroupName, 'wordpress')].TargetGroupArn" \
    --output text | head -1)

echo "Target Group ARN: $TARGET_GROUP_ARN"

# Target group detayları
aws elbv2 describe-target-groups \
    --target-group-arns $TARGET_GROUP_ARN \
    --region $REGION \
    --query 'TargetGroups[0].[
        TargetGroupName,
        Protocol,
        Port,
        HealthCheckProtocol,
        HealthCheckPath,
        HealthCheckIntervalSeconds,
        HealthyThresholdCount,
        UnhealthyThresholdCount
    ]' \
    --output table
```

#### 8.3 Target Health (En Önemli!)
```bash
# Target'ların health durumu
aws elbv2 describe-target-health \
    --target-group-arn $TARGET_GROUP_ARN \
    --region $REGION \
    --query 'TargetHealthDescriptions[*].[Target.Id,Target.Port,TargetHealth.State,TargetHealth.Reason]' \
    --output table
```

**Beklenen Sonuç:**
- State: `healthy`
- Reason: Boş veya olmayabilir

**Unhealthy Durumları:**
- `initial`: Henüz health check başlamadı
- `unhealthy`: Health check başarısız
- `draining`: Instance terminate ediliyor
- `unused`: Target group'a kayıtlı değil

#### 8.4 ALB Listener'ları
```bash
# ALB listener yapılandırması
ALB_ARN=$(aws elbv2 describe-load-balancers \
    --region $REGION \
    --query "LoadBalancers[?contains(LoadBalancerName, 'wordpress')].LoadBalancerArn" \
    --output text)

aws elbv2 describe-listeners \
    --load-balancer-arn $ALB_ARN \
    --region $REGION \
    --output table
```

#### 8.5 ALB Access Logs (Eğer aktifse)
```bash
# Access log yapılandırması
aws elbv2 describe-load-balancer-attributes \
    --load-balancer-arn $ALB_ARN \
    --region $REGION \
    --query 'Attributes[?Key==`access_logs.s3.enabled`]' \
    --output table
```

#### 8.6 Canlı Target Health İzleme
```bash
# Her 10 saniyede bir target health durumu
watch -n 10 "aws elbv2 describe-target-health \
    --target-group-arn $TARGET_GROUP_ARN \
    --region $REGION \
    --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State]' \
    --output table"
```

---

## Test 9: Security Groups

### Amaç
Tüm security group'ların doğru yapılandırıldığını ve port kurallarının çalıştığını doğrulamak.

### Komutlar

#### 9.1 VPC'deki Tüm Security Group'ları Listele
```bash
# VPC'deki tüm SG'ler
aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --region $REGION \
    --query 'SecurityGroups[*].[GroupName,GroupId,Description]' \
    --output table
```

#### 9.2 ALB Security Group Kuralları
```bash
# ALB SG'nin ingress/egress kuralları
ALB_SG=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=*alb*" \
    --region $REGION \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

echo "ALB Security Group: $ALB_SG"

# Ingress rules (gelen trafik)
echo "=== INGRESS RULES ==="
aws ec2 describe-security-groups \
    --group-ids $ALB_SG \
    --region $REGION \
    --query 'SecurityGroups[0].IpPermissions[*].[
        FromPort,
        ToPort,
        IpProtocol,
        IpRanges[0].CidrIp
    ]' \
    --output table

# Egress rules (giden trafik)
echo "=== EGRESS RULES ==="
aws ec2 describe-security-groups \
    --group-ids $ALB_SG \
    --region $REGION \
    --query 'SecurityGroups[0].IpPermissionsEgress[*].[
        FromPort,
        ToPort,
        IpProtocol,
        IpRanges[0].CidrIp
    ]' \
    --output table
```

**Beklenen ALB SG Kuralları:**
- Ingress: Port 80 (HTTP) from 0.0.0.0/0
- Egress: All traffic

#### 9.3 WordPress Instance Security Group
```bash
# WordPress SG
WP_SG=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=*wordpress*" \
    --region $REGION \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

echo "WordPress Security Group: $WP_SG"

aws ec2 describe-security-groups \
    --group-ids $WP_SG \
    --region $REGION \
    --query 'SecurityGroups[0].IpPermissions[*]' \
    --output json | jq -r '.[] | "Port \(.FromPort)-\(.ToPort) from \(.UserIdGroupPairs[0].GroupId // .IpRanges[0].CidrIp)"'
```

**Beklenen WordPress SG Kuralları:**
- Port 80 from ALB SG
- Port 22 from Bastion SG

#### 9.4 RDS Security Group
```bash
# RDS SG
RDS_SG=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=*rds*" \
    --region $REGION \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

echo "RDS Security Group: $RDS_SG"

aws ec2 describe-security-groups \
    --group-ids $RDS_SG \
    --region $REGION \
    --query 'SecurityGroups[0].IpPermissions[*]' \
    --output json | jq -r '.[] | "Port \(.FromPort) from \(.UserIdGroupPairs[0].GroupId)"'
```

**Beklenen RDS SG Kuralları:**
- Port 3306 from WordPress SG
- Port 3306 from Bastion SG

#### 9.5 Bastion Security Group
```bash
# Bastion SG
BASTION_SG=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=*bastion*" \
    --region $REGION \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

echo "Bastion Security Group: $BASTION_SG"

aws ec2 describe-security-groups \
    --group-ids $BASTION_SG \
    --region $REGION \
    --query 'SecurityGroups[0].IpPermissions[*].[FromPort,IpRanges[0].CidrIp]' \
    --output table
```

**Beklenen Bastion SG Kuralları:**
- Port 22 from VPN VPC CIDR (10.1.0.0/16)

#### 9.6 Tüm Security Group'ları Dışa Aktar
```bash
# JSON formatında tüm SG kuralları
aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --region $REGION \
    --output json > security-groups-backup.json

echo "Security groups exported to security-groups-backup.json"
```

---

## Test 10: SNS Email Subscription

### Amaç
CloudWatch alarmlarının email gönderebilmesi için SNS subscription'ın doğru yapılandırıldığını kontrol etmek.

### Komutlar

#### 10.1 SNS Topic Bilgileri
```bash
# SNS topic detayları
aws sns get-topic-attributes \
    --topic-arn $SNS_TOPIC \
    --region $REGION \
    --output json | jq -r '.Attributes | {
        TopicArn:.TopicArn,
        DisplayName:.DisplayName,
        SubscriptionsConfirmed:.SubscriptionsConfirmed,
        SubscriptionsPending:.SubscriptionsPending
    }'
```

#### 10.2 Subscription Durumu
```bash
# Tüm subscription'lar
aws sns list-subscriptions-by-topic \
    --topic-arn $SNS_TOPIC \
    --region $REGION \
    --query 'Subscriptions[*].[Endpoint,Protocol,SubscriptionArn]' \
    --output table
```

**Durumlar:**
- `arn:aws:sns:...`: ✅ Confirmed (aktif)
- `PendingConfirmation`: ⏳ Email onayı bekleniyor
- `Deleted`: ❌ Silinmiş

#### 10.3 Email Onayı Kontrolü
```bash
# Subscription ARN'ini al
SUB_ARN=$(aws sns list-subscriptions-by-topic \
    --topic-arn $SNS_TOPIC \
    --region $REGION \
    --query 'Subscriptions[0].SubscriptionArn' \
    --output text)

if [ "$SUB_ARN" = "PendingConfirmation" ]; then
    echo "❌ Email subscription pending confirmation!"
    echo "Check your email inbox for AWS SNS confirmation."
elif [ "$SUB_ARN" = "Deleted" ]; then
    echo "❌ Subscription deleted!"
else
    echo "✅ Email subscription is confirmed!"
    echo "Subscription ARN: $SUB_ARN"
fi
```

#### 10.4 Test Email Gönder
```bash
# SNS üzerinden test email gönder
aws sns publish \
    --topic-arn $SNS_TOPIC \
    --subject "Test: WordPress Monitoring" \
    --message "This is a test notification from your WordPress Auto Scaling infrastructure.

Timestamp: $(date)
Region: $REGION
ASG: $ASG_NAME

If you received this, SNS email notifications are working correctly!" \
    --region $REGION
```

**Email gelmediyse:**
1. Spam/Junk klasörünü kontrol et
2. Subscription pending ise email'deki "Confirm subscription" linkine tıkla
3. Email adresi terraform.dev.tfvars'da doğru mu kontrol et

#### 10.5 SNS Topic Policy Kontrol
```bash
# Topic'in publish yetkisi var mı?
aws sns get-topic-attributes \
    --topic-arn $SNS_TOPIC \
    --region $REGION \
    --query 'Attributes.Policy' \
    --output text | jq -r '.Statement[] | {
        Effect:.Effect,
        Principal:.Principal,
        Action:.Action
    }'
```

#### 10.6 CloudWatch Alarmların SNS Bağlantısı
```bash
# Hangi alarmlar bu SNS topic'i kullanıyor?
aws cloudwatch describe-alarms \
    --region $REGION \
    --query "MetricAlarms[?contains(AlarmActions[0], 'wordpress-dev-alarms')].AlarmName" \
    --output table
```

---

## Yük Testi: Auto Scaling

### Amaç
CPU yükü oluşturarak Auto Scaling'in çalıştığını doğrulamak.

### Ön Hazırlık

```bash
# İlk WordPress instance'ın IP'sini al
WP_INSTANCE_IP=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names $ASG_NAME \
    --region $REGION \
    --query 'AutoScalingGroups[0].Instances[0].InstanceId' \
    --output text | xargs aws ec2 describe-instances \
    --instance-ids {} \
    --region $REGION \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text)

echo "WordPress Instance IP: $WP_INSTANCE_IP"
```

### Test Adımları

#### 1. Başlangıç Durumunu Kaydet
```bash
# Mevcut ASG durumu
echo "=== BAŞLANGIÇ DURUMU ==="
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names $ASG_NAME \
    --region $REGION \
    --query 'AutoScalingGroups[0].{
        Desired:DesiredCapacity,
        Current:length(Instances),
        Instances:Instances[*].[InstanceId,HealthStatus]
    }' \
    --output json | jq
```

#### 2. stress-ng Kur (WordPress Instance'da)
```bash
# SSH ile bağlan ve stress-ng kur
ssh -i ~/.ssh/wordpress-key.pem \
    -o ProxyCommand="ssh -W %h:%p -i ~/.ssh/wordpress-key.pem ec2-user@$BASTION_IP" \
    ec2-user@$WP_INSTANCE_IP \
    "sudo dnf install -y stress-ng"
```

#### 3. CPU Yük Testi Başlat (5 dakika)

##### Terminal 1: CPU Stress
```bash
# 100% CPU yükü oluştur (5 dakika = 300 saniye)
ssh -i ~/.ssh/wordpress-key.pem \
    -o ProxyCommand="ssh -W %h:%p -i ~/.ssh/wordpress-key.pem ec2-user@$BASTION_IP" \
    ec2-user@$WP_INSTANCE_IP \
    "stress-ng --cpu 1 --cpu-load 100 --timeout 300s --metrics-brief"
```

**Çıktı:**
```
stress-ng: info: [xxxxx] dispatching hogs: 1 cpu
stress-ng: info: [xxxxx] successful run completed in 300.00s
```

##### Terminal 2: ASG İzleme
```bash
# Her 10 saniyede bir ASG durumunu göster
watch -n 10 "echo '=== ASG STATUS ===' && \
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names $ASG_NAME \
    --region $REGION \
    --query 'AutoScalingGroups[0].{
        Desired:DesiredCapacity,
        Current:length(Instances),
        Min:MinSize,
        Max:MaxSize
    }' && \
echo '' && echo '=== INSTANCES ===' && \
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names $ASG_NAME \
    --region $REGION \
    --query 'AutoScalingGroups[0].Instances[*].[InstanceId,LifecycleState,HealthStatus]' \
    --output table"
```

##### Terminal 3: CloudWatch Alarm İzleme
```bash
# CPU High alarm durumu
watch -n 30 "aws cloudwatch describe-alarms \
    --alarm-names 'wordpress-dev-cpu-high' \
    --region $REGION \
    --query 'MetricAlarms[0].[AlarmName,StateValue,StateReason]' \
    --output table"
```

#### 4. Beklenen Sonuçlar

**Timeline:**
- **T+0:** CPU stress başladı, Current CPU: ~5% → 100%
- **T+5 min:** CloudWatch 2. datapoint topladı (2 x 5 dakika evaluation period)
- **T+5 min:** Alarm state: OK → ALARM
- **T+5 min:** SNS email gönderildi: "ALARM: wordpress-dev-cpu-high"
- **T+5 min:** Scale-up policy tetiklendi
- **T+6 min:** Desired capacity: 1 → 2
- **T+6-8 min:** Yeni instance başlatılıyor (launching → pending → InService)
- **T+8 min:** Current instances: 2 (healthy)

**5 dakika sonra stress bitti:**
- **T+10 min:** CPU: 100% → ~5%
- **T+15 min:** CloudWatch 2. düşük datapoint topladı
- **T+15 min:** Alarm state: ALARM → OK
- **T+15 min:** SNS email gönderildi: "OK: wordpress-dev-cpu-high"
- **T+20 min:** Scale-down policy tetiklendi (cooldown period sonrası)
- **T+20 min:** Desired capacity: 2 → 1
- **T+21 min:** Bir instance terminate ediliyor
- **T+22 min:** Current instances: 1

#### 5. Detaylı Metrik Kontrolü
```bash
# CPU metriklerini grafik olarak göster (son 30 dakika)
aws cloudwatch get-metric-statistics \
    --namespace AWS/EC2 \
    --metric-name CPUUtilization \
    --dimensions Name=AutoScalingGroupName,Value=$ASG_NAME \
    --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average,Maximum \
    --region $REGION \
    --query 'Datapoints | sort_by(@, &Timestamp)[*].[Timestamp,Average,Maximum]' \
    --output table
```

#### 6. Scaling Activity Log
```bash
# Son scaling aktivitelerini görüntüle
aws autoscaling describe-scaling-activities \
    --auto-scaling-group-name $ASG_NAME \
    --region $REGION \
    --max-records 5 \
    --query 'Activities[*].[StartTime,StatusCode,Description,Cause]' \
    --output table
```

**Beklenen Aktiviteler:**
```
Launching a new EC2 instance: i-xxxxx. Cause: alarm triggered...
Terminating EC2 instance: i-xxxxx. Cause: alarm state changed...
```

#### 7. Email Kontrolü

Alarmlar tetiklendiğinde şu email'leri almalısınız:

**Email 1: ALARM State**
```
Subject: ALARM: "wordpress-dev-cpu-high" in US East (N. Virginia)

You are receiving this email because your Amazon CloudWatch Alarm
"wordpress-dev-cpu-high" in the US East (N. Virginia) region has
entered the ALARM state.

Alarm Details:
- State Change: OK -> ALARM
- Reason: Threshold Crossed: 2 datapoints [XX, XX] were greater than threshold (50)
```

**Email 2: OK State**
```
Subject: OK: "wordpress-dev-cpu-high" in US East (N. Virginia)

Alarm Details:
- State Change: ALARM -> OK
- Reason: Threshold Crossed: 2 datapoints [XX, XX] were not greater than threshold (50)
```

### Sorun Giderme

#### CPU %100 olmasına rağmen scale-out olmadı
```bash
# 1. Alarm durumunu kontrol et
aws cloudwatch describe-alarms \
    --alarm-names "wordpress-dev-cpu-high" \
    --region $REGION

# 2. Datapoints kontrolü (2 datapoint gerekli)
# Evaluation periods * period = 2 * 5min = 10 dakika bekle

# 3. Alarm actions var mı?
aws cloudwatch describe-alarms \
    --alarm-names "wordpress-dev-cpu-high" \
    --region $REGION \
    --query 'MetricAlarms[0].AlarmActions'

# 4. ASG max size limitine ulaştı mı?
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names $ASG_NAME \
    --region $REGION \
    --query 'AutoScalingGroups[0].[DesiredCapacity,MaxSize]'
```

#### Yeni instance launch oldu ama unhealthy
```bash
# Target group health check
aws elbv2 describe-target-health \
    --target-group-arn $TARGET_GROUP_ARN \
    --region $REGION

# Instance üzerinde web server çalışıyor mu?
ssh -i ~/.ssh/wordpress-key.pem \
    -o ProxyCommand="ssh -W %h:%p -i ~/.ssh/wordpress-key.pem ec2-user@$BASTION_IP" \
    ec2-user@$NEW_INSTANCE_IP \
    "systemctl status nginx && curl localhost"
```

#### Scale-in çok uzun sürdü
```bash
# Cooldown period kontrolü
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names $ASG_NAME \
    --region $REGION \
    --query 'AutoScalingGroups[0].DefaultCooldown'

# Scale-down policy cooldown
aws autoscaling describe-policies \
    --auto-scaling-group-name $ASG_NAME \
    --region $REGION \
    --query 'ScalingPolicies[?PolicyType==`StepScaling`]'
```

---

## 📊 Test Sonuçları Özeti

Test tamamlandıktan sonra sonuçları kaydetmek için:

```bash
# Test raporu oluştur
cat > test-report-$(date +%Y%m%d-%H%M%S).txt << EOF
WordPress Auto Scaling - Manuel Test Raporu
============================================
Test Tarihi: $(date)
Region: $REGION
Environment: dev

1. WordPress Web Access: [✓/✗]
   URL: $WORDPRESS_URL

2. VPN Server: [✓/✗]
   IP: $VPN_SERVER_IP
   Config: ~/.vpn/${VPN_USER}.ovpn

3. Bastion Host: [✓/✗]
   IP: $BASTION_IP

4. Auto Scaling Group: [✓/✗]
   Name: $ASG_NAME
   Instances: X/X healthy

5. CloudWatch Alarms: [✓/✗]
   CPU High: OK/ALARM
   CPU Low: OK/ALARM
   Unhealthy Hosts: OK/ALARM

6. RDS MySQL: [✓/✗]
   Endpoint: $RDS_ENDPOINT
   Status: available

7. EFS File System: [✓/✗]
   ID: $EFS_ID
   State: available

8. Load Balancer: [✓/✗]
   DNS: $ALB_DNS
   Healthy Targets: X/X

9. Security Groups: [✓/✗]
   Total SG: X

10. SNS Subscription: [✓/✗]
    Topic: $SNS_TOPIC
    Status: Confirmed/Pending

Auto Scaling Yük Testi:
- Scale-out Time: X minutes
- Scale-in Time: X minutes
- Max Instances Reached: X
- Emails Received: [✓/✗]

Notlar:
-
EOF

echo "Test raporu oluşturuldu: test-report-*.txt"
```

---

## 🔗 Hızlı Referans Komutları

```bash
# Tüm terraform outputs
terraform output

# ASG durumu (tek satır)
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $ASG_NAME --region $REGION --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Current:length(Instances)}'

# Alarm durumları (tek satır)
aws cloudwatch describe-alarms --alarm-name-prefix "wordpress-dev" --region $REGION --query 'MetricAlarms[*].[AlarmName,StateValue]' --output text

# Target health (tek satır)
aws elbv2 describe-target-health --target-group-arn $TARGET_GROUP_ARN --region $REGION --query 'TargetHealthDescriptions[*].TargetHealth.State' --output text

# WordPress instance IP'leri
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $ASG_NAME --region $REGION --query 'AutoScalingGroups[0].Instances[*].InstanceId' --output text | xargs -I {} aws ec2 describe-instances --instance-ids {} --region $REGION --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text
```

---

## ✅ Test Checklist

Tüm testleri tamamlamak için bu checklist'i kullanın:

- [ ] WordPress web sitesine erişebildim
- [ ] VPN server'a SSH ile bağlanabildim
- [ ] VPN config dosyasını indirdim
- [ ] VPN ile bağlanabildim
- [ ] Bastion host'a SSH ile eriştim
- [ ] WordPress instance'larına ProxyCommand ile eriştim
- [ ] ASG instance sayısı doğru
- [ ] CloudWatch alarmları görüntüledim
- [ ] RDS'ye SSH tunnel ile bağlandım
- [ ] MySQL sorguları çalıştırdım
- [ ] EFS mount edildiğini doğruladım
- [ ] ALB target'ları healthy
- [ ] Security group kurallarını kontrol ettim
- [ ] SNS email subscription onayladım
- [ ] Test email aldım
- [ ] CPU stress test yaptım
- [ ] Scale-out çalıştı (1 → 2 instance)
- [ ] Scale-in çalıştı (2 → 1 instance)
- [ ] CloudWatch alarm email'leri aldım

---

**Tebrikler!** Tüm testleri manuel olarak tamamladınız.

İleride hızlı test için: `./scripts/run-tests.sh` 🚀
