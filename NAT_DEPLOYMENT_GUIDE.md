# WeatherAlert - NAT/Private Network Deployment Guide

## 🚨 Your Server Configuration

Your Ubuntu server is behind a NAT (Network Address Translation) device:

- **Internal/Private IP**: `192.168.3.5` (on enp3s0)
- **External/Public IP**: `119.93.148.180` (on your router)
- **Network**: Behind NAT/Router

This means your server is NOT directly accessible from the internet and requires **port forwarding** configuration.

---

## 🌐 Network Topology

```
                     INTERNET
                         │
                         │
                         ▼
        ┌────────────────────────────────┐
        │  Router/Gateway                │
        │  Public IP: 119.93.148.180    │
        │  (Accessible from Internet)    │
        └───────────────┬────────────────┘
                        │ NAT
                        │
            Local Network (192.168.3.x)
                        │
                        ▼
        ┌────────────────────────────────┐
        │  Ubuntu Server                 │
        │  Private IP: 192.168.3.5      │
        │  (Only accessible locally)     │
        │                                │
        │  WeatherAlert Application      │
        └────────────────────────────────┘
```

**Without Port Forwarding:**
- ❌ `http://119.93.148.180/weatherapp` → NOT WORKING (blocked by router)
- ✅ `http://192.168.3.5/weatherapp` → Works only from local network

**With Port Forwarding:**
- ✅ `http://119.93.148.180/weatherapp` → WORKING (forwarded to 192.168.3.5)
- ✅ `http://192.168.3.5/weatherapp` → Works from local network

---

## ⚙️ Required Configuration Steps

### Step 1: Find Your Gateway/Router

```bash
# On your Ubuntu server
ip route show default

# Output will be something like:
# default via 192.168.3.1 dev enp3s0
#              ^^^^^^^^^^^
#              This is your router's IP
```

Common router IPs:
- `192.168.3.1` (likely for your network)
- `192.168.1.1`
- `192.168.0.1`
- `10.0.0.1`

### Step 2: Access Router Admin Panel

Open a web browser and go to your router's IP address:

```
http://192.168.3.1
```

**Login credentials** (if you haven't changed them):
- Check the label on your router
- Common defaults:
  - Username: `admin`, Password: `admin`
  - Username: `admin`, Password: `password`
  - Username: `admin`, Password: (blank)

### Step 3: Configure Port Forwarding

Look for a section called (varies by router brand):
- **Port Forwarding**
- **Virtual Server**
- **NAT Forwarding**
- **Applications & Gaming**
- **Advanced Settings → Port Forwarding**

#### Create These Rules:

| Rule Name | External Port | Internal IP | Internal Port | Protocol | Description |
|-----------|---------------|-------------|---------------|----------|-------------|
| HTTP-WeatherApp | 80 | 192.168.3.5 | 80 | TCP | Web traffic |
| HTTPS-WeatherApp | 443 | 192.168.3.5 | 443 | TCP | Secure web |
| SSH-Server | 22 | 192.168.3.5 | 22 | TCP | Remote access |

**Screenshot Example (varies by router):**
```
Service Name: WeatherApp-HTTP
External Port: 80
Internal IP: 192.168.3.5
Internal Port: 80
Protocol: TCP
[Enable] ✓
```

### Step 4: Save Router Configuration

- Click **Apply** or **Save**
- Router may need to reboot
- Wait 1-2 minutes for changes to take effect

### Step 5: Configure Ubuntu Firewall

```bash
# SSH to your Ubuntu server
ssh bccbsis-py-admin@192.168.3.5

# Allow HTTP and HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 22/tcp
sudo ufw enable

# Check firewall status
sudo ufw status
```

### Step 6: Deploy with Updated Configuration

The deployment scripts have been updated to handle both IPs:

```bash
# From Windows PowerShell
.\deploy_scripts\windows_deploy.ps1

# Or manually
scp deploy_scripts/deploy_to_server.sh bccbsis-py-admin@192.168.3.5:/tmp/
ssh bccbsis-py-admin@192.168.3.5
chmod +x /tmp/deploy_to_server.sh
sudo /tmp/deploy_to_server.sh
```

---

## 🧪 Testing After Port Forwarding

### Test 1: From Inside Local Network

```bash
# From your Windows machine (if on same network)
# Open browser:
http://192.168.3.5/weatherapp

# Or use curl:
curl http://192.168.3.5/weatherapp/
```

### Test 2: From Internet (Public Access)

```bash
# From your phone (using mobile data, not WiFi)
# Or ask a friend to test
http://119.93.148.180/weatherapp

# Or use online service:
# Visit: https://www.whatsmyip.org/port-scanner/
# Enter: 119.93.148.180
# Port: 80
# Should show: OPEN
```

### Test 3: Verify Port Forwarding

```bash
# From an external network (mobile data, different location)
curl -I http://119.93.148.180/weatherapp/

# Should return:
# HTTP/1.1 200 OK
# or
# HTTP/1.1 302 Found (redirect)
```

---

## 🔍 Common Router Brands - How to Configure

### TP-Link Router
1. Login to `http://192.168.3.1`
2. Go to **Advanced** → **NAT Forwarding** → **Virtual Servers**
3. Click **Add**
4. Fill in the port forwarding details
5. Click **Save**

### D-Link Router
1. Login to `http://192.168.3.1`
2. Go to **Advanced** → **Port Forwarding**
3. Enable Port Forwarding
4. Add rules
5. Click **Save Settings**

### Netgear Router
1. Login to `http://192.168.3.1` or `http://routerlogin.net`
2. Go to **Advanced** → **Advanced Setup** → **Port Forwarding/Port Triggering**
3. Select **Port Forwarding**
4. Click **Add Custom Service**
5. Fill in details
6. Click **Apply**

### Asus Router
1. Login to `http://192.168.3.1`
2. Go to **WAN** → **Virtual Server / Port Forwarding**
3. Enable Port Forwarding
4. Add rules
5. Click **Apply**

### Linksys Router
1. Login to `http://192.168.3.1`
2. Go to **Applications & Gaming** → **Port Range Forwarding**
3. Add Application
4. Fill in details
5. Click **Save Settings**

---

## ⚠️ Important Notes

### For SSH Access from Internet

If you want to SSH from outside your network:

```bash
# You'll need to use the public IP:
ssh bccbsis-py-admin@119.93.148.180

# Instead of:
ssh bccbsis-py-admin@192.168.3.5  # Only works locally
```

### Security Considerations

Since you're exposing your server to the internet:

1. **Strong passwords**: Change default passwords
2. **SSH key authentication**: Better than passwords
3. **Fail2ban**: Install to prevent brute force
4. **Regular updates**: Keep system updated
5. **Firewall**: Only open necessary ports

```bash
# Install fail2ban for security
sudo apt install fail2ban -y
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
```

### Dynamic IP Issues

If your **public IP changes** (dynamic IP from ISP):

**Option 1: Dynamic DNS Service**
```bash
# Use services like:
- No-IP (www.noip.com)
- DynDNS
- Duck DNS (www.duckdns.org)

# Get a free domain like:
yourapp.ddns.net → points to your changing IP
```

**Option 2: Check IP Regularly**
```bash
# Find your current public IP:
curl ifconfig.me
curl icanhazip.com
curl ipecho.net/plain

# If changed, update port forwarding
```

---

## 🛠️ Troubleshooting

### Issue: Port Forwarding Not Working

**Check 1: Verify router has port forwarding enabled**
```bash
# From outside your network, check if port is open:
nmap -p 80 119.93.148.180
# Should show: 80/tcp open http
```

**Check 2: Verify Ubuntu firewall**
```bash
sudo ufw status
# Should show:
# 80/tcp    ALLOW    Anywhere
```

**Check 3: Verify Nginx is listening**
```bash
sudo netstat -tlnp | grep :80
# Should show:
# tcp  0  0.0.0.0:80  0.0.0.0:*  LISTEN  <pid>/nginx
```

**Check 4: Test locally first**
```bash
curl http://192.168.3.5/weatherapp/
# Should return HTML or redirect
```

### Issue: Can't Access Router Admin

```bash
# Reset router to defaults (last resort)
# Find reset button on router, hold 10 seconds

# Or find router IP:
ip route show default
arp -a
```

### Issue: Multiple Devices Behind NAT

If you have multiple servers on `192.168.3.x`:

**Option 1: Use different external ports**
```
Public:80 → Server1:192.168.3.5:80
Public:8080 → Server2:192.168.3.6:80
```

**Option 2: Use subdomains** (requires DNS)
```
app1.yourdomain.com → 192.168.3.5:80
app2.yourdomain.com → 192.168.3.6:80
```

---

## 📋 Deployment Checklist for NAT Setup

- [ ] Find router IP address (`ip route show default`)
- [ ] Access router admin panel
- [ ] Configure port forwarding (80, 443, 22)
- [ ] Save router configuration
- [ ] Configure Ubuntu firewall (`ufw`)
- [ ] Deploy application (updated scripts)
- [ ] Test from local network (`http://192.168.3.5/weatherapp`)
- [ ] Test from internet (`http://119.93.148.180/weatherapp`)
- [ ] Verify port 80 is open (nmap or online scanner)
- [ ] Setup security (fail2ban, strong passwords)
- [ ] Document your public IP (in case it changes)
- [ ] Consider Dynamic DNS if IP changes frequently

---

## 🚀 Quick Deploy Commands for NAT Setup

### From Windows (on same network):

```powershell
# Option 1: PowerShell script
.\deploy_scripts\windows_deploy.ps1

# Option 2: Manual
scp deploy_scripts/deploy_to_server.sh bccbsis-py-admin@192.168.3.5:/tmp/
ssh bccbsis-py-admin@192.168.3.5
sudo chmod +x /tmp/deploy_to_server.sh
sudo /tmp/deploy_to_server.sh
```

### Access URLs After Deployment:

```
From Local Network:  http://192.168.3.5/weatherapp
From Internet:       http://119.93.148.180/weatherapp (after port forwarding)
```

---

## 📊 Summary

| Component | Internal (Local) | External (Internet) |
|-----------|------------------|---------------------|
| **Server IP** | 192.168.3.5 | 119.93.148.180 |
| **Access from** | Same network only | Anywhere (with port forwarding) |
| **SSH command** | `ssh user@192.168.3.5` | `ssh user@119.93.148.180` |
| **Web URL** | `http://192.168.3.5/weatherapp` | `http://119.93.148.180/weatherapp` |
| **Configuration needed** | None | Port forwarding on router |

---

## ✅ Next Steps

1. **Configure port forwarding on your router** (most important!)
2. **Deploy using the updated scripts**
3. **Test from local network first**
4. **Test from internet (mobile data)**
5. **Setup security measures**

---

Your WeatherAlert application will work perfectly once port forwarding is configured! 🎉

