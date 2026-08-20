# helm-charts
![release workflow](https://github.com/FirstClose/helm-charts/actions/workflows/release.yml/badge.svg?branch=main)  
Helm Charts used for Firstclose Deployments  

## GitOps Solution Overview

This repo (highlighted below) is the packaging layer of the pipeline: it defines
reusable Helm charts per app type and publishes them as a Helm chart repository via
`release.yml` (chart-releaser). [`argocd`](https://github.com/FirstClose/argocd)
references these published charts by version, and [`devops-firstclose`](https://github.com/FirstClose/devops-firstclose)
provisions the AKS clusters they get deployed onto.

```mermaid
flowchart TD
    subgraph APP["📦 Application Repos<br/>(react, nestjs, aspnet, vite, fcone, ...)"]
        A1["Source Code Push / PR"]
    end

    subgraph CIRUN["⚙️ CI Pipeline<br/>(GitHub Actions, per app repo)"]
        B1["Build & Test"]
        B2["Build Docker Image"]
        B3["Push Image to ACR"]
    end

    A1 --> B1 --> B2 --> B3

    subgraph HC["⎈ helm-charts repo"]
        direction TB
        C1["Reusable Helm Charts<br/>per app type / service"]
        C2["release.yml<br/>(chart-releaser)"]
        C3["Published Chart Repo<br/>firstclose.github.io/helm-charts"]
        C1 --> C2 --> C3
    end

    subgraph DEVOPS["🏗️ devops-firstclose repo"]
        direction TB
        D1["Terraform IaC<br/>AKS clusters, certificates, networking"]
        D2["deploy_infra.yml<br/>CI/CD for infra"]
        D3["Automation Scripts<br/>helm_env_update.py, DR jobs"]
        D1 --> D2
    end

    subgraph ARGOCD["🚀 argocd repo"]
        direction TB
        E1["Application / ApplicationSet<br/>manifests per app type"]
        E2["Per-Environment Values<br/>develop / qa / staging / prod / sandbox"]
        E3["Projects & Core Resources<br/>cert-manager, secrets, schema-registry"]
        E1 --> E2
    end

    B3 -- "new image tag" --> D3
    D3 -- "opens PR to update values" --> E2

    D2 -- "provisions" --> F[("AKS Clusters")]
    F --> G{{"ArgoCD Controller"}}

    E1 --> G
    E3 --> G
    C3 -- "chart source (repoURL + version)" --> G

    G -- "sync / deploy" --> H["Running Workloads<br/>per environment namespace"]

    classDef highlight fill:#fff3b0,stroke:#d4a017,stroke-width:3px,color:#000;
    class C1,C2,C3 highlight
```

**This repo's role:** hosts each service's Helm chart under `charts/` (react,
nestjs, aspnet, vite, fcone, kafka, nifi, limacharlie, ...). On merge to `main`,
`release.yml` packages and publishes new chart versions to the GitHub Pages chart
repo consumed by `argocd`.

## Usage

[Helm](https://helm.sh) must be installed to use the charts.  Please refer to
Helm's [documentation](https://helm.sh/docs) to get started.

Once Helm has been set up correctly, add the repo as follows:

  helm repo add firstclose https://firstclose.github.io/helm-charts

If you had already added this repo earlier, run `helm repo update` to retrieve
the latest versions of the packages.  You can then run `helm search repo
FirstClose` to see the charts.

To install the <chart-name> chart:

    helm install my-<chart-name> firstclose/<chart-name>

To uninstall the chart:

    helm delete my-<chart-name>
