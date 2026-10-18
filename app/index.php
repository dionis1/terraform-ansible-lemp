<?php
$dbStatus = "Disconnected";
$httpCode = 200;

try {
    $pdo = new PDO(
        sprintf(
            "mysql:host=%s;dbname=%s;charset=utf8mb4",
            getenv("DB_HOST"),
            getenv("DB_NAME")
        ),
        getenv("DB_USER"),
        getenv("DB_PASSWORD"),
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_TIMEOUT => 3,
        ]
    );

    $pdo->query("SELECT 1");
    $dbStatus = "Connected";
} catch (PDOException $e) {
    $dbStatus = "Unavailable";
    $httpCode = 503;
}

http_response_code($httpCode);
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">

    <title>Terraform + Ansible | DevOps Infrastructure Project</title>

    <style>
        * {
            box-sizing: border-box;
        }

        body {
            font-family: system-ui, sans-serif;
            background: #0f172a;
            color: #e2e8f0;
            margin: 0;
            line-height: 1.7;
        }

        .container {
            max-width: 950px;
            margin: auto;
            padding: 50px 20px;
        }

        h1, h2 {
            color: #6ee7b7;
        }

        h1 {
            font-size: 2.4rem;
            margin-bottom: 10px;
        }

        h2 {
            margin-top: 0;
        }

        .subtitle {
            color: #94a3b8;
            font-size: 1.1rem;
        }

        .card {
            background: #1e293b;
            padding: 28px;
            border-radius: 14px;
            margin-top: 25px;
            border: 1px solid #334155;
        }

        .flow {
            background: #020617;
            padding: 20px;
            border-radius: 10px;
            text-align: center;
            font-family: monospace;
            color: #93c5fd;
            line-height: 2.2;
            overflow-wrap: anywhere;
        }

        .tags span {
            display: inline-block;
            background: #334155;
            padding: 5px 12px;
            border-radius: 8px;
            margin: 5px 5px 5px 0;
            font-size: 0.9rem;
        }

        .success {
            color: #4ade80;
            font-weight: bold;
        }

        .error {
            color: #f87171;
            font-weight: bold;
        }

        li {
            margin: 10px 0;
        }

        code {
            color: #93c5fd;
        }

        footer {
            text-align: center;
            color: #94a3b8;
            margin-top: 45px;
            font-size: 0.9rem;
        }
    </style>
</head>

<body>
<div class="container">

    <header>
        <h1>DevOps Infrastructure Automation</h1>

        <p class="subtitle">
            Terraform + Ansible + Docker + LEMP Stack
        </p>

        <p>
            A hands-on DevOps portfolio project demonstrating how to
            provision infrastructure, automate Linux configuration,
            and deploy a containerized web application.
        </p>

        <div class="tags">
            <span>Terraform</span>
            <span>Ansible</span>
            <span>Linux</span>
            <span>Docker</span>
            <span>Docker Compose</span>
            <span>NGINX</span>
            <span>PHP-FPM</span>
            <span>MariaDB</span>
        </div>
    </header>

    <section class="card">
        <h2>01 — Project Goal</h2>

        <p>
            The goal of this project is to automate the deployment of
            a complete Linux-based web application environment.
        </p>

        <p>
            Instead of manually creating a virtual machine,
            installing packages, and starting containers,
            the infrastructure and configuration are defined as code.
        </p>

        <p>
            This approach makes the environment easier to reproduce,
            maintain, troubleshoot, and rebuild.
        </p>
    </section>

    <section class="card">
        <h2>02 — Architecture</h2>

        <div class="flow">
            Terraform<br>
            ↓<br>
            Ubuntu Virtual Machine (KVM / libvirt)<br>
            ↓<br>
            Ansible Configuration Management<br>
            ↓<br>
            Docker Engine + Docker Compose<br>
            ↓<br>
            NGINX → PHP-FPM → MariaDB
        </div>
    </section>

    <section class="card">
        <h2>03 — How I Built It</h2>

        <ol>
            <li>
                <strong>Infrastructure provisioning:</strong>
                Used Terraform with the libvirt provider to create
                an Ubuntu virtual machine with configurable CPU,
                memory, storage, and networking.
            </li>

            <li>
                <strong>Operating system initialization:</strong>
                Used cloud-init to configure the initial Linux user,
                SSH authentication, and essential packages.
            </li>

            <li>
                <strong>Configuration management:</strong>
                Created reusable Ansible roles to configure Ubuntu
                and install system packages.
            </li>

            <li>
                <strong>Docker automation:</strong>
                Used Ansible to install Docker Engine and the Docker
                Compose plugin from Docker's official repository.
            </li>

            <li>
                <strong>Application deployment:</strong>
                Used Docker Compose to define NGINX, PHP-FPM,
                and MariaDB as separate services.
            </li>

            <li>
                <strong>Verification:</strong>
                Used Ansible execution results, container status,
                and application/database connectivity checks
                to validate the environment.
            </li>
        </ol>
    </section>

    <section class="card">
        <h2>04 — DevOps Practices</h2>

        <ul>
            <li>
                <strong>Infrastructure as Code:</strong>
                Terraform defines the virtual infrastructure.
            </li>

            <li>
                <strong>Configuration as Code:</strong>
                Ansible roles manage the Linux configuration.
            </li>

            <li>
                <strong>Idempotency:</strong>
                Repeated Ansible runs avoid unnecessary changes.
            </li>

            <li>
                <strong>Containerization:</strong>
                Docker isolates the application services.
            </li>

            <li>
                <strong>Service separation:</strong>
                NGINX, PHP, and MariaDB run independently.
            </li>

            <li>
                <strong>Persistent storage:</strong>
                MariaDB data is stored in a Docker volume.
            </li>

            <li>
                <strong>Credential management:</strong>
                Database passwords are kept outside the
                committed Docker Compose configuration.
            </li>
        </ul>
    </section>

    <section class="card">
        <h2>05 — Live Application Status</h2>

        <p>
            The PHP application performs a real connection test
            against the MariaDB service using PDO.
        </p>

        <p>
            <strong>Database connection:</strong>

            <span class="<?= $dbStatus === 'Connected' ? 'success' : 'error' ?>">
                <?= htmlspecialchars($dbStatus, ENT_QUOTES, 'UTF-8') ?>
            </span>
        </p>

        <p>
            <?php if ($dbStatus === "Connected"): ?>
                The application can successfully communicate
                with MariaDB.
            <?php else: ?>
                The application cannot currently connect to MariaDB.
                Check container health, network connectivity,
                and database credentials.
            <?php endif; ?>
        </p>
    </section>

    <section class="card">
        <h2>06 — Project Scope and Limitations</h2>

        <p>
            This is a local learning and portfolio environment,
            not a production hosting platform.
        </p>

        <p>
            Ansible Vault protects committed database credentials, and automated
            smoke tests verify HTTP and database connectivity. Recovery exercises
            verify persistence and backup restore in this local lab. Dependencies
            are pinned by checksum, digest, or collection version. Future work
            includes CI validation, TLS, monitoring, and scheduled backups.
        </p>
    </section>

    <footer>
        DevOps Portfolio Project —
        Infrastructure Automation with Terraform, Ansible and Docker
    </footer>

</div>
</body>
</html>
