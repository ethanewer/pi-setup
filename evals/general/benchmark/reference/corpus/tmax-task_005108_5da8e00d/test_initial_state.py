# test_initial_state.py
import os
import stat
import subprocess

def test_systemd_services_exist():
    mock_api = "/home/user/.config/systemd/user/k8s-mock-api.service"
    operator = "/home/user/.config/systemd/user/manifest-operator.service"

    assert os.path.isfile(mock_api), f"Missing {mock_api}"
    assert os.path.isfile(operator), f"Missing {operator}"

    with open(operator, "r") as f:
        content = f.read()
        assert "After=" not in content, "Operator service already has After= configured"
        assert "Requires=" not in content, "Operator service already has Requires= configured"

def test_git_repositories_exist():
    bare_repo = "/home/user/k8s-manifests.git"
    workspace_repo = "/home/user/workspace/k8s-manifests"

    assert os.path.isdir(bare_repo), f"Missing bare repo at {bare_repo}"
    assert os.path.isdir(os.path.join(bare_repo, "objects")), f"{bare_repo} is not a valid bare Git repository"

    assert os.path.isdir(workspace_repo), f"Missing workspace repo at {workspace_repo}"
    assert os.path.isdir(os.path.join(workspace_repo, ".git")), f"{workspace_repo} is not a valid Git repository"

def test_push_script_exists():
    push_script = "/home/user/push-manifests.sh"
    assert os.path.isfile(push_script), f"Missing script {push_script}"

    st = os.stat(push_script)
    assert bool(st.st_mode & stat.S_IXUSR), f"{push_script} is not executable"

    with open(push_script, "r") as f:
        content = f.read()
        assert "Deploy Passphrase: " in content, "Push script missing expected prompt"

def test_operator_logs_dir_exists():
    logs_dir = "/home/user/operator-logs"
    assert os.path.isdir(logs_dir), f"Missing logs directory {logs_dir}"