# WordPress Auto Scaling - Hızlı Başlangıç Kılavuzu

Bu kılavuz, WordPress Auto Scaling altyapısını Dev veya Prod ortamı için hızlıca kurmak için gereken adımları içerir.

## 🎯 Ortam Seçimi

Bu proje iki ortamı destekler:

| Ortam | Config Dosyası | WordPress Instance | RDS | ASG | Maliyet/Ay | Kullanım |
|-------|----------------|--------------------|----- |-----|------------|----------|
| **DEV** | `terraform.dev.tfvars` | t2.micro | db.t3.micro (20GB) | 1-2 (desired: 1) | ~$80 | Test ve development |
| **PROD** | `terraform.prod.tfvars` | t3.medium | db.t3.small (50GB) | 2-6 (desired: 2) | ~$200 | Production workload |

## ⚡ Hızlı Dev Kurulumu (5 Dakika)

### 1. Ön Gereksinimler

```bash
# Terraform kurulu mu?
terraform version

# AWS CLI yapılandırılmış mı?
aws sts get-caller-identity

# Doğru bölgede misiniz?
aws configure get region  # us-east-1 olmalı
```

### 2. SSH Key Pair Oluşturun

```bash
aws ec2 create-key-pair \
  --key-name wordpress-key \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/wordpress-key.pem

chmod 400 ~/.ssh/wordpress-key.pem
```

### 3. Dev Ortamını Deploy Edin

**Hızlı Yol** - Helper script kullan:

```bash
./scripts/deploy-dev.sh
```

**Manuel Yol**:

```bash
terraform init
terraform plan -var-file="terraform.dev.tfvars"
terraform apply -var-file="terraform.dev.tfvars"
```

⏱️ **Bekleme Süresi**: 10-15 dakika

### 4. E-posta Onayı

- E-postanızı kontrol edin
- AWS SNS subscription onayını tıklayın

### 5. VPN Kurulumu (10 dakika sonra)

```bash
# VPN config dosyasını indirin
./scripts/download-vpn-config.sh

# VPN'e bağlanın
sudo openvpn --config ~/vpn/hakan.ovpn
```

### 6. WordPress'e Erişin

```bash
# WordPress URL'ini alın
terraform output -var-file="terraform.dev.tfvars" wordpress_url

# Tarayıcınızda açın
```

## 🚀 Production Kurulumu

### 1. Prod Config Dosyasını Düzenleyin

```bash
# terraform.prod.tfvars dosyasını düzenleyin
nano terraform.prod.tfvars

# ÖNEMLİ: db_password değiştirin!
db_password = "YourStrongProductionPassword123!"
alarm_email = "production-alerts@yourcompany.com"
```

### 2. Prod Ortamını Deploy Edin

```bash
# Helper script (ekstra onay ister)
./scripts/deploy-prod.sh
```

Alternatif manuel:

```bash
terraform plan -var-file="terraform.prod.tfvars"
terraform apply -var-file="terraform.prod.tfvars"
```

⏱️ **Bekleme Süresi**: 15-20 dakika (daha fazla kaynak)

## 🗑️ Ortamları Silme

### Dev Ortamını Silme

```bash
./scripts/destroy-dev.sh
```

veya manuel:

```bash
terraform destroy -var-file="terraform.dev.tfvars"
```

### Prod Ortamını Silme (DİKKAT!)

```bash
./scripts/destroy-prod.sh  # Ekstra onay gerektirir
```

⚠️ **UYARI**: Production silme işlemi geri alınamaz!

## 📋 Ortamlar Arası Geçiş

### Şu anda hangi ortam çalışıyor?

```bash
# terraform.tfstate dosyasında kontrol edin
grep '"project_name"' terraform.tfstate
```

### Dev ve Prod'u aynı anda çalıştırabilir miyim?

Hayır. Aynı AWS bölgesinde aynı anda sadece bir ortam çalışabilir.

İki ortamı da çalıştırmak için:
- Farklı AWS bölgeleri kullanın (us-east-1 / us-west-2)
- Veya farklı Terraform workspace'ler kullanın
- Veya farklı dizinlerde ayrı state dosyaları kullanın

## 🧪 Hızlı Test

### WordPress Kurulumu

1. Tarayıcıda WordPress URL'ini açın
2. Dil seçin: **Türkçe**
3. Site bilgilerini girin
4. **WordPress'i Yükle**'ye tıklayın

### Auto Scaling Testi (Dev)

```bash
# VPN'e bağlanın
sudo openvpn --config ~/vpn/hakan.ovpn

# Bastion'a bağlanın (yeni terminal)
ssh -i ~/.ssh/wordpress-key.pem ec2-user@$(terraform output bastion_public_ip)

# WordPress instance'a bağlanın
# (AWS Console'dan instance IP'sini bulun)
ssh ec2-user@<WORDPRESS_PRIVATE_IP>

# CPU yükü oluşturun
stress --cpu 2 --timeout 300
```

**Dev'de Beklenen**: 1 → 2 instance
**Prod'da Beklenen**: 2 → 3-4 instance

## 📊 Ortam Karşılaştırması Detaylı

| Özellik | Dev | Prod |
|---------|-----|------|
| **WordPress Instance** | t2.micro (1 vCPU, 1GB RAM) | t3.medium (2 vCPU, 4GB RAM) |
| **Bastion** | t2.micro | t2.micro |
| **RDS** | db.t3.micro (20GB) | db.t3.small (50GB) |
| **VPN** | t2.micro | t2.micro |
| **ASG Min** | 1 | 2 (HA) |
| **ASG Max** | 2 | 6 |
| **ASG Desired** | 1 | 2 |
| **Multi-AZ RDS** | ✅ Aktif | ✅ Aktif |
| **VPN Default** | ✅ Aktif | ✅ Aktif |
| **Maliyet/Ay** | ~$80 | ~$200 |
| **Kullanım** | Test, Dev | Production |

## 💡 İpuçları

### Dev Ortamı İçin

- Gece kapama: `./scripts/destroy-dev.sh` (sabah tekrar `./scripts/deploy-dev.sh`)
- Maliyetten tasarruf etmek için çalışmadığında silin
- VPN'i kapatıp bastion'a doğrudan bağlanabilirsiniz: `enable_vpn = false`

### Prod Ortamı İçin

- **HER ZAMAN** VPN kullanın (`enable_vpn = true`)
- db_password'u güçlü yapın
- SNS alarm e-posta adresini production team listesi yapın
- Backup stratejisi planlayın (RDS automated backups 7 gün aktif)
- Monitoring dashboard'u düzenli kontrol edin

## 🔧 Sık Karşılaşılan Sorunlar

### "Hangi tfvars dosyasını kullanıyorum?"

```bash
# Her terraform komutunda -var-file belirtin
terraform plan -var-file="terraform.dev.tfvars"
terraform apply -var-file="terraform.dev.tfvars"
terraform destroy -var-file="terraform.dev.tfvars"

# veya helper script'leri kullanın (otomatik doğru dosyayı kullanır)
./scripts/deploy-dev.sh
./scripts/deploy-prod.sh
```

### "State dosyası karıştı"

```bash
# Mevcut state'i yedekleyin
cp terraform.tfstate terraform.tfstate.backup

# Yeni kurulum yapıyorsanız state'i silin
rm -f terraform.tfstate terraform.tfstate.backup

# Sonra deploy edin
./scripts/deploy-dev.sh
```

### "Dev'den Prod'a nasıl geçiş yaparım?"

```bash
# 1. Dev'i sil
./scripts/destroy-dev.sh

# 2. Prod'u kur
./scripts/deploy-prod.sh
```

## 📚 Daha Fazla Bilgi

Detaylı bilgi için [README.md](README.md) dosyasına bakın.

## ✅ Başarı Kriterleri

### Dev Ortamı
- [ ] WordPress kurulum sayfası açılıyor
- [ ] Admin paneline giriş yapılabiliyor
- [ ] VPN bağlantısı çalışıyor
- [ ] Bastion'a VPN üzerinden erişilebiliyor
- [ ] Auto Scaling test edildi (1 → 2 instance)

### Prod Ortamı
- [ ] İki instance healthy durumda
- [ ] WordPress prod URL'i çalışıyor
- [ ] CloudWatch alarms kuruldu
- [ ] E-posta bildirimleri geliyor
- [ ] Backup retention 7 gün
- [ ] SSL/HTTPS kuruldu (opsiyonel)
- [ ] Monitoring dashboard aktif

---

**İyi Çalışmalar!** 🚀
