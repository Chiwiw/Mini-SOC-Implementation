# File: attacker-node/Dockerfile
FROM kalilinux/kali-rolling

# Update repository dan install tools tempur
RUN apt-get update && apt-get install -y \
    curl \
    nmap \
    sshpass \
    iputils-ping \
    && rm -rf /var/lib/apt/lists/*

# Perintah agar kontainer tidak langsung mati (stay awake)
CMD ["tail", "-f", "/dev/null"]
