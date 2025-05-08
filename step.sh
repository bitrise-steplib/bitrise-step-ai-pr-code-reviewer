#!/usr/bin/env bash
set -eo pipefail

echo "Configuring AI code review step with Claude Code..."

# Input validation
if [ -z "${claude_api_key}" ]; then
  echo "Error: No Claude API key provided. Please provide your Anthropic API key as 'claude_api_key' input."
  exit 1
fi

if [ -z "${git_branch_dest}" ]; then
  echo "Error: Destination branch is not specified."
  exit 1
fi

if [ -z "${git_branch_src}" ]; then
  echo "Error: Source branch is not specified."
  exit 1
fi

if [ -z "${review_prompt}" ]; then
  echo "Error: No review prompt specified."
  exit 1
fi

if [ -z "${deploy_dir}" ]; then
  echo "Error: Deploy directory not specified."
  exit 1
fi

if [ -z "${bitrise_services_token}" ]; then
  echo "Warning: No Bitrise services token provided. Annotations will not be created."
fi

echo "Installing Claude Code CLI..."
set -x
# Install the AI review tool, claude code
npm install -g @anthropic-ai/claude-code

# Set the API key for claude
export ANTHROPIC_API_KEY="${claude_api_key}"

echo "Fetching git differences..."
# Get the list of changed files
git fetch --unshallow || git fetch --all
git diff origin/${git_branch_dest}...origin/${git_branch_src} | tee "${deploy_dir}/changed_files.diff"

echo "Running AI review with Claude Code..."

# Create a temporary file for the context
context_file="${deploy_dir}/context.txt"
touch "${context_file}"

# Process context files if provided
if [ -n "${context_files}" ]; then
  echo "Processing additional context files..."
  echo "<context>" >> "${context_file}"
  
  # Process each file path line by line
  while IFS= read -r file_path || [[ -n "$file_path" ]]; do
    # Skip empty lines
    if [ -z "${file_path}" ]; then
      continue
    fi
    
    # Check if file exists
    if [ -f "${file_path}" ]; then
      echo "Adding context from file: ${file_path}"
      echo "<file path=\"${file_path}\">" >> "${context_file}"
      cat "${file_path}" >> "${context_file}"
      echo "</file>" >> "${context_file}"
    else
      echo "Warning: Context file not found: ${file_path}"
    fi
  done <<< "${context_files}"
  
  echo "</context>" >> "${context_file}"
fi

# Add the git diff to the context file
echo "<file path=\"git-changes.diff\">" >> "${context_file}"
cat "${deploy_dir}/changed_files.diff" >> "${context_file}"
echo "</file>" >> "${context_file}"

# Run AI review with the combined context
echo "Running review with context..."
cat "${context_file}" | claude -p "${review_prompt}" | tee "${deploy_dir}/review.txt"

# Add annotations if token is available
if [ -n "${bitrise_services_token}" ]; then
  echo "Creating Bitrise annotations..."
  bitrise plugin install https://github.com/bitrise-io/bitrise-plugins-annotations.git
  cat "${deploy_dir}/review.txt" | bitrise :annotations annotate --context "ai-review" --style "warning"
fi

# Expose the review result as an output
echo "Setting output variables..."
envman add --key BITRISE_AI_REVIEW --value "$(cat ${deploy_dir}/review.txt)"

echo "AI code review complete! Results saved to ${deploy_dir}/review.txt"