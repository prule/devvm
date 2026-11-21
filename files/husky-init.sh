# Added by devvm: secret scan before every commit (devvm README, Secret scanning).
if [ "${n:-}" = pre-commit ]; then
  /usr/local/bin/devvm-secret-scan || exit 1
fi
