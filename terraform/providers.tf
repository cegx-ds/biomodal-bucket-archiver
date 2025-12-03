terraform {
  cloud {
    organization = "cegx"
    workspaces {
      name = "prj-biomodal-bucket-archiver"
    }
  }
}
