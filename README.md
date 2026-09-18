terraformがミスって最初からやり直したい場合、proxmox側で
```
qm stop 300 && \
qm destroy 300 && \
pveum user delete kubernetes-dev@pve && \
pveum user delete kubernetes-csi-dev@pve && \
pveum role delete CCM-dev && \
pveum role delete Kubernetes-CSI-dev
```


```
qm stop 200 && \
qm destroy 200 && \
pveum user delete kubernetes@pve && \
pveum user delete kubernetes-csi@pve && \
pveum role delete CCM && \
pveum role delete Kubernetes-CSI
```