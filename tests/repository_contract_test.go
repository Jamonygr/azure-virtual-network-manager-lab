package contracts

import (
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"
)

func repositoryRoot(t *testing.T) string {
	t.Helper()
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	return root
}

func readFiles(t *testing.T, root string, include func(string) bool) map[string]string {
	t.Helper()
	result := map[string]string{}
	err := filepath.Walk(root, func(path string, entry os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if entry.IsDir() && (entry.Name() == ".git" || entry.Name() == ".terraform") {
			return filepath.SkipDir
		}
		if entry.IsDir() || !include(path) {
			return nil
		}
		content, readErr := os.ReadFile(path)
		if readErr != nil {
			return readErr
		}
		relative, relErr := filepath.Rel(root, path)
		if relErr != nil {
			return relErr
		}
		result[filepath.ToSlash(relative)] = string(content)
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	return result
}

func TestTerraformStaysControlPlaneOnly(t *testing.T) {
	files := readFiles(t, repositoryRoot(t), func(path string) bool {
		return strings.HasSuffix(path, ".tf")
	})
	forbidden := []*regexp.Regexp{
		regexp.MustCompile(`resource\s+"azurerm_(linux|windows)_virtual_machine`),
		regexp.MustCompile(`resource\s+"azurerm_network_interface"`),
		regexp.MustCompile(`resource\s+"azurerm_public_ip"`),
		regexp.MustCompile(`resource\s+"azurerm_firewall`),
		regexp.MustCompile(`resource\s+"azurerm_(virtual_network|local_network|vpn)_gateway`),
		regexp.MustCompile(`resource\s+"azurerm_nat_gateway"`),
		regexp.MustCompile(`resource\s+"azurerm_log_analytics_workspace"`),
		regexp.MustCompile(`resource\s+"azurerm_monitor_diagnostic_setting"`),
		regexp.MustCompile(`resource\s+"azurerm_virtual_network_peering"`),
		regexp.MustCompile(`resource\s+"azurerm_route_table"`),
		regexp.MustCompile(`resource\s+"azapi_`),
	}
	for name, content := range files {
		for _, pattern := range forbidden {
			if pattern.MatchString(content) {
				t.Errorf("%s contains forbidden resource matching %s", name, pattern)
			}
		}
	}
}

func TestTerraformUsesOnlyLocalStateAndPinnedProvider(t *testing.T) {
	files := readFiles(t, repositoryRoot(t), func(path string) bool { return strings.HasSuffix(path, ".tf") })
	for name, content := range files {
		if regexp.MustCompile(`backend\s+"(azurerm|s3|gcs|remote|cloud)"`).MatchString(content) {
			t.Errorf("%s configures a remote backend", name)
		}
	}
	versions := files["versions.tf"]
	for _, required := range []string{`version = "= 5.2.0"`, `resource_provider_registrations = "none"`} {
		if !strings.Contains(versions, required) {
			t.Errorf("versions.tf must contain %q", required)
		}
	}
}

func TestIPAMSiblingPoolsAreSerialized(t *testing.T) {
	contentBytes, err := os.ReadFile(filepath.Join(repositoryRoot(t), "modules", "ipam-pools", "main.tf"))
	if err != nil {
		t.Fatal(err)
	}
	content := string(contentBytes)
	if !strings.Contains(content, "depends_on = [azurerm_network_manager_ipam_pool.hub]") {
		t.Fatal("workload child pool must wait for hub child pool to avoid Azure parent-pool ETag races")
	}
}

func TestIPAMTagKeysAreNormalizedForNoDrift(t *testing.T) {
	contentBytes, err := os.ReadFile(filepath.Join(repositoryRoot(t), "modules", "ipam-pools", "main.tf"))
	if err != nil {
		t.Fatal(err)
	}
	content := string(contentBytes)
	if !strings.Contains(content, "ipam_tags = { for key, value in var.tags : lower(key) => value }") {
		t.Fatal("IPAM tag keys must be lowercase to match Azure's canonical read response")
	}
	if strings.Count(content, "tags               = local.ipam_tags") != 3 {
		t.Fatal("all three IPAM pools must use the normalized tag map")
	}
}

func TestEnvironmentProfilesDifferOnlyByTopology(t *testing.T) {
	root := repositoryRoot(t)
	hubBytes, err := os.ReadFile(filepath.Join(root, "environments", "hub-spoke.tfvars"))
	if err != nil {
		t.Fatal(err)
	}
	meshBytes, err := os.ReadFile(filepath.Join(root, "environments", "mesh.tfvars"))
	if err != nil {
		t.Fatal(err)
	}
	normalize := func(value string) []string {
		lines := strings.Split(strings.ReplaceAll(value, "\r\n", "\n"), "\n")
		for index := range lines {
			if strings.HasPrefix(strings.TrimSpace(lines[index]), "topology_mode") {
				lines[index] = "topology_mode = <MODE>"
			}
		}
		return lines
	}
	left, right := normalize(string(hubBytes)), normalize(string(meshBytes))
	if strings.Join(left, "\n") != strings.Join(right, "\n") {
		t.Fatal("hub-spoke.tfvars and mesh.tfvars differ beyond topology_mode")
	}
}

func TestLifecycleRunnerHasGuaranteedSafeCleanup(t *testing.T) {
	contentBytes, err := os.ReadFile(filepath.Join(repositoryRoot(t), "scripts", "invoke-live-validation.ps1"))
	if err != nil {
		t.Fatal(err)
	}
	content := string(contentBytes)
	required := []string{
		"finally {",
		"Invoke-LabCleanup",
		"terraform-undeploy-goal-state",
		"Invoke-EmptyGoalStateFallback",
		"Wait-GoalStateRemoved",
		"state-after-destroy",
		"hasDeploymentState",
		"-CleanupRun",
		"Invoke-ConnectivityUndeployForMesh",
		"Wait-ConnectivityRemovedForTransition",
		"-replace=module.avnm.azurerm_network_manager_connectivity_configuration.active",
	}
	for _, text := range required {
		if !strings.Contains(content, text) {
			t.Errorf("lifecycle runner is missing %q", text)
		}
	}
	if strings.Contains(content, "AVNM_Managed_ResourceGroup_") && strings.Contains(content, "az group delete") {
		t.Error("lifecycle runner must never blindly delete the shared AVNM managed resource group")
	}
}

func TestCIIsCredentialFreeAndStatic(t *testing.T) {
	root := filepath.Join(repositoryRoot(t), ".github", "workflows")
	files := readFiles(t, root, func(path string) bool {
		return strings.HasSuffix(path, ".yml") || strings.HasSuffix(path, ".yaml")
	})
	if len(files) == 0 {
		t.Fatal("no GitHub Actions workflow found")
	}
	for name, content := range files {
		lower := strings.ToLower(content)
		for _, forbidden := range []string{
			"azure/login",
			"arm_client_secret",
			"azure_client_id",
			"azure_tenant_id",
			"azure_subscription_id",
			"terraform apply",
			"terraform destroy",
			"terraform plan",
		} {
			if strings.Contains(lower, forbidden) {
				t.Errorf("workflow %s contains forbidden live-cloud pattern %q", name, forbidden)
			}
		}
	}
}

func TestNoCredentialLikeValuesAreCommitted(t *testing.T) {
	root := repositoryRoot(t)
	files := readFiles(t, root, func(path string) bool {
		ext := strings.ToLower(filepath.Ext(path))
		return ext == ".tf" || ext == ".tfvars" || ext == ".yml" || ext == ".yaml" || ext == ".ps1"
	})
	patterns := []*regexp.Regexp{
		regexp.MustCompile(`(?i)(client_secret|access_token|refresh_token)\s*[=:]\s*["'][^"']+["']`),
		regexp.MustCompile(`(?i)-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----`),
	}
	var names []string
	for name := range files {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		for _, pattern := range patterns {
			if pattern.MatchString(files[name]) {
				t.Errorf("%s appears to contain credential material matching %s", name, pattern)
			}
		}
	}
}
