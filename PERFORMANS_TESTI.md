# Auto Scaling Performans Testi - Hızlı Tetikleme

Bu dokümanda, WordPress Auto Scaling altyapısında **hemen tetiklenen** ve **güçlü** performans testleri için komutlar bulunmaktadır.

> **Not:** Bu test TÜM CPU core'larını %100 yüke çıkarır ve CloudWatch alarmını 5-7 dakikada tetikler.

---

## 📋 Hızlı Test Komutu (Kopyala-Yapıştır)

```bash
# Tek komut ile tüm test
INSTANCE_IP=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names wordpress-dev-asg --region us-east-1 --query 'AutoScalingGroups[0].Instances[0].InstanceId' --output text | xargs aws ec2 describe-instances --instance-ids {} --region us-east-1 --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text) && \
BASTION_IP=$(terraform output -raw bastion_public_ip) && \
echo "Instance: $INSTANCE_IP, Bastion: $BASTION_IP" && \
ssh -i ~/.ssh/wordpress-key.pem -o ProxyCommand="ssh -W %h:%p -i ~/.ssh/wordpress-key.pem ec2-user@$BASTION_IP" -o StrictHostKeyChecking=no ec2-user@$INSTANCE_IP 'nohup stress-ng --cpu 0 --cpu-load 100 --timeout 600s > /tmp/stress.log 2>&1 & echo "✓ Agresif CPU stress başlatıldı (10 dakika, TÜM core)"'
```

---

## 🚀 Adım Adım Test

### Adım 1: Başlangıç Durumu

```bash
# Mevcut ASG durumunu kaydet
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names wordpress-dev-asg \
    --region us-east-1 \
    --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Min:MinSize,Max:MaxSize,Current:length(Instances)}'

# Beklenen: Desired: 1, Current: 1
```

### Adım 2: Instance Bilgilerini Al

```bash
# WordPress instance private IP
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names wordpress-dev-asg \
    --region us-east-1 \
    --query 'AutoScalingGroups[0].Instances[0].InstanceId' \
    --output text)

INSTANCE_IP=$(aws ec2 describe-instances \
    --instance-ids $INSTANCE_ID \
    --region us-east-1 \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text)

# Bastion IP
BASTION_IP=$(terraform output -raw bastion_public_ip)

echo "Instance IP: $INSTANCE_IP"
echo "Bastion IP: $BASTION_IP"
```

### Adım 3: AGRESİF CPU Stress (TÜM CORE'LAR)

```bash
# TÜM CPU core'larını %100 yüke çıkar (10 dakika)
ssh -i ~/.ssh/wordpress-key.pem \
    -o ProxyCommand="ssh -W %h:%p -i ~/.ssh/wordpress-key.pem ec2-user@$BASTION_IP" \
    -o StrictHostKeyChecking=no \
    ec2-user@$INSTANCE_IP \
    'nohup stress-ng --cpu 0 --cpu-load 100 --timeout 600s > /tmp/stress.log 2>&1 & echo "Process ID: $!" && sleep 2 && ps aux | grep stress-ng | grep -v grep'

# Çıktı:
# Process ID: 12345
# ec2-user  12345  99.0  0.0 stress-ng --cpu 0 --cpu-load 100
```

**Parametreler:**
- `--cpu 0`: TÜM core'ları kullan (0 = auto-detect)
- `--cpu-load 100`: %100 yük
- `--timeout 600s`: 10 dakika

---

## 📊 Adım 4: Canlı İzleme (3 Terminal)

### Terminal 1: ASG İzleme

```bash
# Her 30 saniyede bir ASG durumu
watch -n 30 "echo '=== ASG - \$(date +%H:%M:%S) ===' && \
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names wordpress-dev-asg \
    --region us-east-1 \
    --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Current:length(Instances),Instances:Instances[*].[InstanceId,LifecycleState,HealthStatus]}'"
```

### Terminal 2: CloudWatch Alarms

```bash
# Her 30 saniyede bir alarm durumu
watch -n 30 "echo '=== ALARMS - \$(date +%H:%M:%S) ===' && \
aws cloudwatch describe-alarms \
    --alarm-names wordpress-dev-cpu-high wordpress-dev-cpu-low \
    --region us-east-1 \
    --query 'MetricAlarms[*].[AlarmName,StateValue]' \
    --output table"
```

### Terminal 3: Scaling Activities

```bash
# Her 30 saniyede bir scaling aktiviteleri
watch -n 30 "echo '=== SCALING ACTIVITIES ===' && \
aws autoscaling describe-scaling-activities \
    --auto-scaling-group-name wordpress-dev-asg \
    --region us-east-1 \
    --max-records 3 \
    --query 'Activities[*].[StartTime,StatusCode,Description]' \
    --output table"
```

---

## ⏱️ Beklenen Timeline (AGRESİF TEST)

| Zaman | CPU | Alarm | Desired | Current | Olay |
|-------|-----|-------|---------|---------|------|
| T+0 | ~5% | OK | 1 | 1 | Stress başladı |
| T+30s | **100%** | OK | 1 | 1 | TÜM core'lar %100 |
| T+5m | **100%** | **ALARM** | **2** | 1 | CloudWatch 2. datapoint, Scale-up! |
| T+6m | 100% | ALARM | 2 | 1-2 | Yeni instance launching |
| T+7m | 100% | ALARM | 2 | **2** | 2 instance InService |
| T+10m | 5% | ALARM | 2 | 2 | Stress bitti |
| T+15m | 5% | OK | 2 | 2 | Alarm OK'ye döndü |
| T+20m | 5% | ALARM (low) | **1** | 2 | Scale-down |
| T+22m | 5% | ALARM (low) | 1 | **1** | Stable |

**Toplam Süre:** ~22 dakika (scale-out + scale-in)
**Scale-out Süresi:** 5-7 dakika (TÜM core'lar %100 ile)

---

## 🔥 DAHA HIZLI TETİKLEME (3 Dakika)

CloudWatch alarmını daha hızlı tetiklemek için **2 datapoint yerine hemen** tetiklemek isterseniz (sadece test için):

```bash
# CloudWatch alarm'ı 1 datapoint ile tetikle (TESTİÇİN - PROD'da KULLANMA!)
aws cloudwatch put-metric-alarm \
    --alarm-name wordpress-dev-cpu-high \
    --alarm-description "CPU > 50% - FAST TRIGGER" \
    --actions-enabled \
    --alarm-actions $(terraform output -raw scale_up_policy_arn) $(terraform output -raw sns_topic_arn) \
    --metric-name CPUUtilization \
    --namespace AWS/EC2 \
    --statistic Average \
    --dimensions Name=AutoScalingGroupName,Value=wordpress-dev-asg \
    --period 60 \
    --evaluation-periods 1 \
    --datapoints-to-alarm 1 \
    --threshold 50 \
    --comparison-operator GreaterThanThreshold \
    --region us-east-1

echo "✓ Alarm güncellendi: 1 dakika period, 1 datapoint"
echo "⚠️  Stress test sonrası alarm'ı eski haline döndürmeyi unutma!"
```

**Not:** Test sonrası alarm'ı eski haline döndür:

```bash
# Alarm'ı varsayılana döndür (5 dakika period, 2 datapoint)
terraform apply -var-file=terraform.dev.tfvars -auto-approve
```

---

## 📈 Test Sonrası Analiz

### CPU Metrikleri (Son 1 Saat)

```bash
aws cloudwatch get-metric-statistics \
    --namespace AWS/EC2 \
    --metric-name CPUUtilization \
    --dimensions Name=AutoScalingGroupName,Value=wordpress-dev-asg \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average,Maximum \
    --region us-east-1 \
    --query 'Datapoints | sort_by(@, &Timestamp)[*].[Timestamp,Average,Maximum]' \
    --output table
```

### Scaling Timeline

```bash
aws autoscaling describe-scaling-activities \
    --auto-scaling-group-name wordpress-dev-asg \
    --region us-east-1 \
    --max-records 10 \
    --query 'Activities[*].{Time:StartTime,Status:StatusCode,Event:Description,Reason:Cause}' \
    --output table
```

### Alarm History

```bash
aws cloudwatch describe-alarm-history \
    --alarm-name wordpress-dev-cpu-high \
    --region us-east-1 \
    --history-item-type StateUpdate \
    --max-records 10 \
    --query 'AlarmHistoryItems[*].[Timestamp,HistorySummary]' \
    --output table
```

---

## 🛑 Stress Test'i Durdurma

Erken durdurmak isterseniz:

```bash
# Stress process'i kill et
ssh -i ~/.ssh/wordpress-key.pem \
    -o ProxyCommand="ssh -W %h:%p -i ~/.ssh/wordpress-key.pem ec2-user@$BASTION_IP" \
    ec2-user@$INSTANCE_IP \
    'pkill stress-ng && echo "✓ Stress durduruldu"'

# Process kontrolü
ssh -i ~/.ssh/wordpress-key.pem \
    -o ProxyCommand="ssh -W %h:%p -i ~/.ssh/wordpress-key.pem ec2-user@$BASTION_IP" \
    ec2-user@$INSTANCE_IP \
    'ps aux | grep stress-ng'
```

---

## ✅ Başarı Kriterleri

Test başarılı sayılır eğer:

1. ✅ CPU %100'e çıktı (TÜM core'lar)
2. ✅ 5-7 dakika içinde CloudWatch alarm tetiklendi (OK → ALARM)
3. ✅ ASG Desired: 1 → 2 oldu
4. ✅ Yeni instance 2-3 dakikada InService oldu
5. ✅ 2 instance healthy ve load balancer'da registered
6. ✅ SNS email geldi (CPU high alarm)
7. ✅ Stress bittikten 5-10 dakika sonra scale-down başladı
8. ✅ SNS email geldi (CPU low alarm)
9. ✅ ASG Desired: 2 → 1 oldu
10. ✅ Sistem stable duruma döndü (1 instance)

---

## 🎯 Sorun Giderme

### Alarm Tetiklenmedi

```bash
# 1. CPU gerçekten %100 mı?
ssh -i ~/.ssh/wordpress-key.pem \
    -o ProxyCommand="ssh -W %h:%p -i ~/.ssh/wordpress-key.pem ec2-user@$BASTION_IP" \
    ec2-user@$INSTANCE_IP \
    'top -bn1 | grep "Cpu(s)"'

# 2. Stress-ng çalışıyor mu?
ssh -i ~/.ssh/wordpress-key.pem \
    -o ProxyCommand="ssh -W %h:%p -i ~/.ssh/wordpress-key.pem ec2-user@$BASTION_IP" \
    ec2-user@$INSTANCE_IP \
    'ps aux | grep stress-ng | grep -v grep | wc -l'

# 3. CloudWatch metrik gidiyor mu?
aws cloudwatch get-metric-statistics \
    --namespace AWS/EC2 \
    --metric-name CPUUtilization \
    --dimensions Name=InstanceId,Value=$INSTANCE_ID \
    --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 60 \
    --statistics Average \
    --region us-east-1 \
    --query 'Datapoints[-5:] | [*].[Timestamp,Average]' \
    --output table
```

### Instance Launch Olmuyor

```bash
# ASG max size kontrolü
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names wordpress-dev-asg \
    --region us-east-1 \
    --query 'AutoScalingGroups[0].[DesiredCapacity,MaxSize]'

# Eğer Desired = MaxSize ise, max size artır:
# terraform.dev.tfvars'da asg_max_size = 4 yap
# terraform apply -var-file=terraform.dev.tfvars -auto-approve
```

---

## 📝 Test Raporu Şablonu

Test sonrası doldur:

```
=== AUTO SCALING PERFORMANS TEST RAPORU ===

Test Tarihi: ___________________
Test Eden: ____________________

BAŞLANGIÇ DURUMU:
- Desired Capacity: ___
- Current Instances: ___
- Alarm Status: ___________

STRESS TEST:
- Başlangıç: _______ (saat)
- CPU Yükü: %100 TÜM core'lar
- Süre: 10 dakika

SCALE-OUT:
- Alarm Tetikleme: _______ (T+___m) [OK/FAIL]
- Desired: 1 → 2: _______ (T+___m) [OK/FAIL]
- Instance Launch: _______ (T+___m) [OK/FAIL]
- InService: _______ (T+___m) [OK/FAIL]
- SNS Email: [OK/FAIL]

SCALE-IN:
- Alarm Tetikleme: _______ (T+___m) [OK/FAIL]
- Desired: 2 → 1: _______ (T+___m) [OK/FAIL]
- Instance Terminate: _______ (T+___m) [OK/FAIL]
- SNS Email: [OK/FAIL]

SONUÇ: [BAŞARILI/BAŞARISIZ]
NOTLAR:
_________________________________
_________________________________
```

---

**Test başarılar! 🚀**
