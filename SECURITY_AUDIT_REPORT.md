# Helm Charts Security Audit Report

**Audit Date:** 2026-02-05
**Scope:** All Helm charts in repository
**Benchmarks:** Microsoft AKS Security Baseline, CIS Kubernetes Benchmark v1.6
**Overall Risk Level:** HIGH

---

## Executive Summary

This audit examined 13 Helm charts in the repository against Microsoft AKS Security Baseline and CIS Kubernetes Benchmarks. Multiple critical and high-severity security gaps were identified across all charts that should be addressed before production deployment.

### Charts Audited

| Category | Charts |
|----------|--------|
| Standard Application Charts (10) | aspnet, devops, fcone, nestjs, nestjs-microservice, nestjs-ng, nextjs, react, vite |
| Specialized Charts (3) | limacharlie, limacharlie-win, kafka, nifi |

---

## Summary of Findings

| Severity | Count | Description |
|----------|-------|-------------|
| CRITICAL | 6 | Privileged containers, host namespace access, automount tokens, latest tags |
| HIGH | 8 | Missing security contexts, resource limits, NetworkPolicies, RBAC |
| MEDIUM | 4 | Image tags, TLS configuration, ConfigMap usage |
| LOW | 0 | - |

---

## Detailed Findings

### 1. Container Security

#### 1.1 Running as Root (runAsNonRoot, runAsUser)

| Severity | CRITICAL |
|----------|----------|
| Affected Charts | aspnet, devops, fcone, nestjs, nestjs-microservice, nestjs-ng, nextjs, react, vite |
| CIS Benchmark | 5.2.1 - Ensure containers are not running with root user privileges |
| AKS Baseline | Container security context - runAsNonRoot should be true |

**Issue:** No `runAsNonRoot` or `runAsUser` configuration defined. Containers will run as root (UID 0).

**Current Configuration (all affected charts):**
```yaml
# values.yaml
securityContext: {}
  # capabilities:
  #   drop:
  #   - ALL
  # readOnlyRootFilesystem: true
  # runAsNonRoot: true
  # runAsUser: 1000
```

**Exceptions:**
- **NiFi** (COMPLIANT): `securityContext: { runAsUser: 1000, fsGroup: 1000 }`
- **Lima Charlie** (CRITICAL): `securityContext: { privileged: true }` - Runs as root AND privileged
- **Kafka** (N/A): Strimzi operator handles security

**Recommended Fix:**
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
```

---

#### 1.2 Read-Only Root Filesystem

| Severity | HIGH |
|----------|------|
| Affected Charts | aspnet, devops, fcone, nestjs, nestjs-microservice, nestjs-ng, nextjs, react, vite |
| CIS Benchmark | 5.2.2 - Minimize the admission of containers with allowPrivilegeEscalation |

**Issue:** `readOnlyRootFilesystem` not configured or disabled in all standard application charts.

**Impact:** Containers can be modified at runtime, increasing attack surface for malware persistence.

**Recommended Fix:**
```yaml
securityContext:
  readOnlyRootFilesystem: true
```

Note: May require `emptyDir` volumes for writable paths (e.g., `/tmp`, `/var/cache`).

---

#### 1.3 Privilege Escalation

| Severity | HIGH |
|----------|------|
| Affected Charts | aspnet, devops, fcone, nestjs, nestjs-microservice, nestjs-ng, nextjs, react, vite |
| CIS Benchmark | 5.2.5 - Ensure container does not allow privilege escalation |

**Issue:** `allowPrivilegeEscalation` not configured, defaults to `true`.

**Impact:** Allows containers to gain additional privileges after startup via setuid binaries or capabilities.

**Recommended Fix:**
```yaml
securityContext:
  allowPrivilegeEscalation: false
```

---

#### 1.4 Privileged Containers

| Severity | CRITICAL |
|----------|----------|
| Affected Charts | limacharlie, limacharlie-win |
| CIS Benchmark | 5.2.1 - Privileged containers must not be used |

**Files:**
- `charts/limacharlie/templates/limacharlie-sensor-daemonset-linux.yaml` (line 31)
- `charts/limacharlie-win/templates/limacharlie-sensor-daemonset.yaml` (line 36)

**Current Configuration:**
```yaml
securityContext:
  privileged: true
```

**Impact:** Highest severity - full access to host resources, can escape container isolation.

**Business Justification Required:** Lima Charlie is a security monitoring agent that may legitimately require privileged access for system-level monitoring. This should be documented and approved by security team.

---

#### 1.5 Capability Management

| Severity | HIGH |
|----------|------|
| Affected Charts | aspnet, devops, fcone, nestjs, nestjs-microservice, nestjs-ng, nextjs, react, vite |
| CIS Benchmark | 5.2.3 - Ensure containers drop Linux kernel capabilities |

**Issue:** No capabilities dropped; all Linux capabilities available to containers.

**Current Configuration:**
```yaml
securityContext: {}
  # capabilities:
  #   drop:
  #   - ALL
```

**Recommended Fix:**
```yaml
securityContext:
  capabilities:
    drop:
      - ALL
    # add: [] # Only add specific capabilities if absolutely required
```

---

### 2. Resource Management

#### 2.1 CPU/Memory Limits and Requests

| Severity | HIGH |
|----------|------|
| Affected Charts | aspnet, devops, fcone, nestjs, nestjs-microservice, nestjs-ng, nextjs, react, vite |
| CIS Benchmark | 5.1.1 - Ensure CPU and memory limits are set |
| AKS Baseline | All containers must have resource limits and requests defined |

**Issue:** Resources defined as empty `resources: {}` in all standard application charts.

**Current Configuration:**
```yaml
resources: {}
  # limits:
  #   cpu: 100m
  #   memory: 128Mi
  # requests:
  #   cpu: 100m
  #   memory: 128Mi
```

**Impact:**
- Risk of resource exhaustion
- Noisy neighbor problems
- Denial of service vulnerabilities
- Cannot enable resource quotas effectively

**Recommended Fix:**
```yaml
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 128Mi
```

Note: Values should be tuned based on actual application requirements.

---

#### 2.2 Resource Quotas

| Severity | MEDIUM |
|----------|--------|
| Affected Charts | All charts |

**Issue:** No namespace-level ResourceQuota definitions in charts.

**Impact:** Cluster-wide resource exhaustion possible.

**Recommendation:** Implement ResourceQuotas at the namespace level (typically done outside of application charts).

---

### 3. Network Security

#### 3.1 NetworkPolicy

| Severity | HIGH |
|----------|------|
| Affected Charts | All 13 charts |
| CIS Benchmark | 5.3.1 - Ensure network policies are defined and enforced |

**Issue:** No NetworkPolicy resources defined in any chart.

**Impact:**
- No microsegmentation
- Pods can communicate freely with all other pods
- Lateral movement possible if a pod is compromised

**Missing File:** `templates/networkpolicy.yaml` (not present in any chart)

**Recommended Fix:** Create NetworkPolicy for each chart:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "chart.fullname" . }}
spec:
  podSelector:
    matchLabels:
      {{- include "chart.selectorLabels" . | nindent 6 }}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: ingress-nginx
      ports:
        - protocol: TCP
          port: {{ .Values.service.port }}
  egress:
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: UDP
          port: 53  # DNS
    # Add application-specific egress rules
```

---

#### 3.2 Service Types

| Severity | LOW (COMPLIANT) |
|----------|-----------------|
| Status | All application charts default to `service.type: ClusterIP` |

**Current Configuration:**
```yaml
service:
  type: ClusterIP
  port: 80
```

**Assessment:** Safe default - services not directly exposed outside cluster.

---

#### 3.3 Ingress TLS Configuration

| Severity | MEDIUM |
|----------|--------|
| Affected Charts | All charts with ingress resources |

**Issue:** Ingress TLS is optional and commented out by default.

**Current Configuration:**
```yaml
ingress:
  enabled: false
  # ...
  tls: []
  #  - secretName: chart-example-tls
  #    hosts:
  #      - chart-example.local
```

**Impact:** When ingress is enabled, TLS may not be configured, allowing unencrypted traffic.

**Recommendation:** Enforce TLS when ingress is enabled:
```yaml
ingress:
  tls:
    - secretName: {{ include "chart.fullname" . }}-tls
      hosts:
        - {{ .Values.ingress.host }}
```

---

### 4. Secrets Management

#### 4.1 External Secrets Integration

| Severity | LOW (COMPLIANT) |
|----------|-----------------|
| Status | Using External Secrets Operator with Azure Key Vault |

**Current Configuration (charts/*/templates/secrets.yaml):**
```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: {{ include "chart.fullname" . }}-secrets
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: azure-store
  target:
    name: {{ include "chart.fullname" . }}-secrets
    creationPolicy: Owner
```

**Assessment:**
- Secrets not stored in Git
- Automatic refresh every 1 hour
- Azure Key Vault integration (AKS-aligned)
- Proper `secretKeyRef` usage in deployments

---

#### 4.2 Secret References in Deployments

| Severity | LOW (COMPLIANT) |
|----------|-----------------|

**Current Configuration:**
```yaml
{{- range $key, $value := .Values.secrets }}
- name: {{ $value }}
  valueFrom:
    secretKeyRef:
      name: {{ $fullName }}-secrets
      key: {{ $value }}
{{- end }}
```

**Assessment:** All charts use `secretKeyRef`, no plain text secrets in deployments.

---

#### 4.3 ConfigMap Usage

| Severity | MEDIUM |
|----------|--------|

**Current Status:** ConfigMaps used for non-sensitive configuration data only (port numbers, environment flags).

**Recommendation:** Document what should NEVER go in ConfigMaps:
- Passwords
- API keys
- Tokens
- Connection strings with credentials
- Private keys

---

### 5. Pod Security

#### 5.1 Pod-Level SecurityContext

| Severity | HIGH |
|----------|------|
| Affected Charts | aspnet, devops, fcone, nestjs, nestjs-microservice, nestjs-ng, nextjs, react, vite |

**Issues:**
1. Pod-level `securityContext` empty
2. No `fsGroup` defined for file permissions
3. No seccomp profiles configured

**Current Configuration:**
```yaml
podSecurityContext: {}
  # fsGroup: 2000
```

**Recommended Fix:**
```yaml
podSecurityContext:
  fsGroup: 1000
  seccompProfile:
    type: RuntimeDefault
```

---

#### 5.2 ServiceAccount - automountServiceAccountToken

| Severity | CRITICAL |
|----------|----------|
| Affected Charts | All charts with service account creation |
| CIS Benchmark | 5.1.6 - Ensure service account admission controller is enabled |

**Issue:** `automountServiceAccountToken` defaults to `true`, automatically mounting service account tokens in pods.

**Impact:**
- Pods automatically get service account token mounted
- Increases attack surface for token theft
- Enables potential privilege escalation if pod is compromised

**Current Configuration (templates/serviceaccount.yaml):**
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "chart.fullname" . }}
  labels:
    {{- include "chart.labels" . | nindent 4 }}
```

**Recommended Fix:**
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "chart.fullname" . }}
  labels:
    {{- include "chart.labels" . | nindent 4 }}
automountServiceAccountToken: false
```

Or in deployment spec:
```yaml
spec:
  automountServiceAccountToken: false
```

---

#### 5.3 Host Namespace Access

| Severity | CRITICAL |
|----------|----------|
| Affected Charts | limacharlie, limacharlie-win |
| CIS Benchmark | 5.2.4 (hostNetwork), 5.2.6 (hostPID) |

**Files:**
- `charts/limacharlie/templates/limacharlie-sensor-daemonset-linux.yaml` (lines 54-55)
- `charts/limacharlie-win/templates/limacharlie-sensor-daemonset.yaml` (lines 37-38)

**Current Configuration:**
```yaml
hostNetwork: true
hostPID: true
dnsPolicy: ClusterFirstWithHostNet
```

**Issues:**
1. `hostNetwork: true` - Pod shares host network namespace
2. `hostPID: true` - Pod can see all host processes
3. Combined with `privileged: true` creates maximum exposure

**Business Justification:** Lima Charlie is a security agent requiring system-level monitoring. This configuration may be necessary but should be:
- Documented with security team approval
- Monitored for unauthorized changes
- Restricted via NetworkPolicy

---

### 6. Image Security

#### 6.1 Image Pull Policy

| Severity | LOW (ACCEPTABLE) |
|----------|------------------|

**Standard Charts Configuration:**
```yaml
image:
  pullPolicy: IfNotPresent
```

**Assessment:** Safe default - pulls only if not locally cached.

**Exception:** nestjs-microservice uses `pullPolicy: Always`
- File: `charts/nestjs-microservice/values.yaml` (line 12)
- Impact: Forces pull of latest image (good for development, potential performance impact in production)

---

#### 6.2 Image Tags

| Severity | CRITICAL/HIGH |
|----------|---------------|

**CRITICAL - Using `:latest` tag:**

| Chart | File | Current Value |
|-------|------|---------------|
| limacharlie | `values.yaml` line 5 | `refractionpoint/limacharlie_sensor:latest` |

**HIGH - Undefined tags (empty string):**

| Chart | Current Value |
|-------|---------------|
| aspnet | `tag: ""` |
| devops | `tag: ""` |
| fcone | `tag: ""` |
| nestjs-ng | `tag: ""` |
| nextjs | `tag: ""` |
| react | `tag: ""` |
| vite | `tag: ""` |

**MEDIUM - Development tags:**

| Chart | Current Value |
|-------|---------------|
| nestjs | `tag: "develop"` |
| nestjs-microservice | `tag: "develop"` |

**CIS Benchmark:** 5.3.2 - Ensure image tag is specific and not "latest"

**Impact:**
- Unpredictable deployments
- Potential for using outdated or unvetted images
- No reproducibility guarantees

**Recommended Fix:**
```yaml
image:
  repository: your-registry/your-image
  tag: "v1.2.3"  # Specific semantic version
  # Or use digest for maximum security:
  # digest: "sha256:abc123..."
```

---

#### 6.3 Image Registry

| Severity | MEDIUM |
|----------|--------|

**Current Usage:**
- Some charts use GitHub Container Registry (`ghcr.io/firstclose/...`) - Good
- Some charts use `nginx` as placeholder - Not production-ready
- Lima Charlie uses Docker Hub (`refractionpoint/...`) - Acceptable with pinned version

**Recommendation:**
- Use private registry for all production images
- Enable image scanning in registry
- Consider image signing/verification

---

### 7. RBAC (Role-Based Access Control)

#### 7.1 Missing RBAC Definitions

| Severity | HIGH |
|----------|------|
| Affected Charts | All charts |
| CIS Benchmark | 5.4.1 - Ensure default service account does not have cluster-admin role |

**Issue:** ServiceAccounts created conditionally, but NO corresponding Role/RoleBinding resources defined.

**Missing Files:**
- `templates/role.yaml` - Not present in any chart
- `templates/rolebinding.yaml` - Not present in any chart

**Impact:**
1. Service accounts have no explicit permissions (inherits default)
2. Cannot verify least privilege principle
3. Potential for unnecessary cluster permissions

**Recommended Fix:**

Create `templates/role.yaml`:
```yaml
{{- if .Values.serviceAccount.create -}}
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: {{ include "chart.fullname" . }}
  labels:
    {{- include "chart.labels" . | nindent 4 }}
rules:
  # Add minimal required permissions
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list", "watch"]
{{- end }}
```

Create `templates/rolebinding.yaml`:
```yaml
{{- if .Values.serviceAccount.create -}}
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: {{ include "chart.fullname" . }}
  labels:
    {{- include "chart.labels" . | nindent 4 }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: {{ include "chart.fullname" . }}
subjects:
  - kind: ServiceAccount
    name: {{ include "chart.serviceAccountName" . }}
    namespace: {{ .Release.Namespace }}
{{- end }}
```

---

## CIS Kubernetes Benchmark Compliance Matrix

| Control | Description | Status | Affected Charts |
|---------|-------------|--------|-----------------|
| 5.1.1 | Ensure CPU and memory limits are set | FAIL | All standard apps |
| 5.1.6 | Ensure service account tokens are not automatically mounted | FAIL | All with SA |
| 5.2.1 | Minimize admission of privileged containers | FAIL | limacharlie* |
| 5.2.2 | Minimize admission of containers with allowPrivilegeEscalation | FAIL | All standard apps |
| 5.2.3 | Minimize admission of containers without capability drops | FAIL | All standard apps |
| 5.2.4 | Minimize admission of containers with hostNetwork | FAIL | limacharlie* |
| 5.2.5 | Minimize admission of containers with privilege escalation | FAIL | All standard apps |
| 5.2.6 | Minimize admission of containers with hostPID | FAIL | limacharlie* |
| 5.3.1 | Ensure network policies are in effect | FAIL | All charts |
| 5.3.2 | Ensure image tags are specific | FAIL | Multiple charts |
| 5.4.1 | Ensure default SA is not used | PARTIAL | SA created but no RBAC |

*Lima Charlie may have legitimate business justification for privileged access

---

## Microsoft AKS Security Baseline Gaps

| Requirement | Status | Notes |
|-------------|--------|-------|
| Container runtime security defaults | FAIL | Security contexts not configured |
| Pod security policies/standards | FAIL | No PSS enforcement configured |
| Network segmentation | FAIL | No NetworkPolicies defined |
| Resource quotas | FAIL | No quotas defined |
| Azure Key Vault integration | PASS | External Secrets configured |
| Managed identities | PARTIAL | Service accounts created |

---

## Chart-by-Chart Risk Summary

| Chart | Risk Level | Critical Issues | High Issues |
|-------|------------|-----------------|-------------|
| limacharlie | CRITICAL | Privileged, hostNetwork, hostPID, :latest tag | - |
| limacharlie-win | CRITICAL | Privileged, hostNetwork, hostPID | - |
| aspnet | HIGH | automountServiceAccountToken | No securityContext, resources, NetworkPolicy |
| devops | HIGH | automountServiceAccountToken | No securityContext, resources, NetworkPolicy |
| fcone | HIGH | automountServiceAccountToken | No securityContext, resources, NetworkPolicy |
| nestjs | HIGH | automountServiceAccountToken | "develop" tag, no securityContext, resources |
| nestjs-microservice | HIGH | automountServiceAccountToken | "develop" tag, no securityContext |
| nestjs-ng | HIGH | automountServiceAccountToken | No securityContext, resources, disabled probes |
| nextjs | HIGH | automountServiceAccountToken | No securityContext, resources, NetworkPolicy |
| react | HIGH | automountServiceAccountToken | No securityContext, resources, NetworkPolicy |
| vite | HIGH | automountServiceAccountToken | No securityContext, resources, NetworkPolicy |
| nifi | MEDIUM | - | Missing NetworkPolicy, RBAC |
| kafka | MEDIUM | - | Verify Strimzi resource limits |

---

## Remediation Plan

### Priority 1 - Implement Immediately

1. **Add SecurityContext to all standard application charts**
   ```yaml
   podSecurityContext:
     fsGroup: 1000
     seccompProfile:
       type: RuntimeDefault

   securityContext:
     runAsNonRoot: true
     runAsUser: 1000
     allowPrivilegeEscalation: false
     readOnlyRootFilesystem: true
     capabilities:
       drop:
         - ALL
   ```

2. **Define Resource Requests and Limits**
   ```yaml
   resources:
     limits:
       cpu: 500m
       memory: 512Mi
     requests:
       cpu: 100m
       memory: 128Mi
   ```

3. **Disable automountServiceAccountToken**
   - Add to ServiceAccount or PodSpec

4. **Pin image tags**
   - Replace `:latest` with specific versions
   - Replace empty tags with specific versions
   - Replace `develop` with stable versions for production

### Priority 2 - Implement in Next Release

1. **Create NetworkPolicy resources** for all charts
2. **Create RBAC definitions** (Role, RoleBinding)
3. **Document Lima Charlie privileged access justification**
4. **Enforce TLS on ingress resources**

### Priority 3 - Long-term Improvements

1. Implement Pod Security Standards at cluster level
2. Add container image scanning to CI/CD pipeline
3. Implement Helm chart security scanning
4. Enable Kubernetes audit logging
5. Consider OPA/Gatekeeper for policy enforcement

---

## Appendix: Recommended values.yaml Template

```yaml
# Security-hardened values.yaml template

replicaCount: 1

image:
  repository: your-registry/your-image
  pullPolicy: IfNotPresent
  tag: "v1.0.0"  # Always use specific version

serviceAccount:
  create: true
  automount: false  # Explicitly disable token mounting
  annotations: {}
  name: ""

podSecurityContext:
  fsGroup: 1000
  seccompProfile:
    type: RuntimeDefault

securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
      - ALL

resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 128Mi

service:
  type: ClusterIP
  port: 80

ingress:
  enabled: false
  className: "nginx"
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
  hosts:
    - host: chart-example.local
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: chart-example-tls
      hosts:
        - chart-example.local

networkPolicy:
  enabled: true  # Enable by default
```

---

## Document Information

| Field | Value |
|-------|-------|
| Document Version | 1.0 |
| Audit Date | 2026-02-05 |
| Auditor | Claude Code (Automated) |
| Next Review | 2026-05-05 |
| Classification | Internal |
