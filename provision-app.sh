#!/bin/bash
set -euxo pipefail

# install node LTS.
# see https://github.com/nodesource/distributions#debinstall
NODE_MAJOR_VERSION=20
apt-get update
apt-get install -y ca-certificates curl gnupg
mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR_VERSION.x nodistro main" \
    > /etc/apt/sources.list.d/nodesource.list
apt-get update
apt-get install -y nodejs
node --version
npm --version

# add the app user.
groupadd --system app
adduser \
    --system \
    --disabled-login \
    --no-create-home \
    --gecos '' \
    --ingroup app \
    --home /opt/app \
    app
install -d -o root -g app -m 750 /opt/app

# add the app user to the imds group to allow it to access the imds ip address.
usermod --append --groups imds app

# create an example http server and run it as a systemd service.
pushd /opt/app
cat >main.js <<EOF
import http from "http";

function createRequestListener(instanceId) {
    return (request, response) => {
        const serverAddress = \`\${request.socket.localAddress}:\${request.socket.localPort}\`;
        const clientAddress = \`\${request.socket.remoteAddress}:\${request.socket.remotePort}\`;
        const message = \`Instance ID: \${instanceId}
Node.js Version: \${process.versions.node}
Server Address: \${serverAddress}
Client Address: \${clientAddress}
Request URL: \${request.url}
\`;
        console.log(message);
        response.writeHead(200, {"Content-Type": "text/plain"});
        response.write(message);
        response.end();
    };
}

function main(instanceId, port) {
    const server = http.createServer(createRequestListener(instanceId));
    server.listen(port);
}

// see https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instancedata-data-retrieval.html
// see https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-metadata-v2-how-it-works.html
async function getInstanceId() {
    const tokenResponse = await fetch("http://169.254.169.254/latest/api/token", {
        method: "PUT",
        headers: {
            "X-aws-ec2-metadata-token-ttl-seconds": 30,
        }
    });
    const token = await tokenResponse.text();
    const instanceIdResponse = await fetch("http://169.254.169.254/latest/meta-data/instance-id", {
        headers: {
            "X-aws-ec2-metadata-token": token,
        }
    });
    const instanceId = await instanceIdResponse.text();
    return instanceId;
}

main(await getInstanceId(), process.argv[2]);
EOF
cat >package.json <<'EOF'
{
    "name": "app",
    "description": "example application",
    "version": "1.0.0",
    "license": "MIT",
    "type": "module",
    "main": "main.js",
    "dependencies": {}
}
EOF
npm install
popd

# launch the app.
cat >/etc/systemd/system/app.service <<EOF
[Unit]
Description=Example Azure Web Application
After=network.target

[Service]
Type=simple
User=app
Group=app
AmbientCapabilities=CAP_NET_BIND_SERVICE
Environment=NODE_ENV=production
ExecStart=/usr/bin/node main.js 80
WorkingDirectory=/opt/app
Restart=on-abort

[Install]
WantedBy=multi-user.target
EOF
systemctl enable app
systemctl start app

# try it.
sleep .2
wget -qO- localhost/try
