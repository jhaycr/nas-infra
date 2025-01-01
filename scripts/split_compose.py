import os
from pathlib import Path

def remove_anchors(service_block):
    """Remove specified anchors from the service block."""
    lines = service_block.split('\n')
    filtered_lines = []
    skip_next = False
    
    for line in lines:
        if skip_next:
            skip_next = False
            continue
            
        if '<<: *common-keys' in line:
            continue
            
        if '<<: *common-env' in line:
            continue
            
        if '- *localtime' in line or '- *storage' in line:
            continue
            
        filtered_lines.append(line)
    
    return '\n'.join(filtered_lines)

def extract_service_block(content, service_name):
    """Extract just the service definition block."""
    lines = content.split('\n')
    service_block = []
    in_service = False
    
    service_block.append("---")
    service_block.append("services:")
    service_block.append("")  # Add blank line after services:
    
    for i, line in enumerate(lines):
        if f"  {service_name}:" in line:
            in_service = True
            service_block.append(f" {service_name}:")
            continue
            
        if in_service:
            if line.strip() and not line.startswith('  '):
                break
            if line.strip() and line.startswith('  ') and ':' in line and not line.startswith('    '):
                if not service_name in line:
                    break
            
            if line.strip():
                processed_line = line[2:] if line.startswith('    ') else line
                service_block.append(processed_line)
    
    service_block_str = '\n'.join(service_block)
    return remove_anchors(service_block_str)

def update_main_compose(file_path, services):
    """Update the main docker-compose file to include service-specific files."""
    with open(file_path, 'r') as f:
        content = f.readlines()

    # Find the includes section
    include_start = -1
    include_end = -1
    in_include = False
    
    for i, line in enumerate(content):
        if line.strip() == 'include:':
            include_start = i
            in_include = True
        elif in_include and line.strip() and not line.startswith(' '):
            include_end = i
            break
    
    if include_end == -1:
        include_end = len(content)

    # Get existing includes
    existing_includes = set()
    for line in content[include_start:include_end]:
        if line.strip().startswith('- path:'):
            existing_includes.add(line.strip())

    # Create new includes for services
    new_includes = []
    found_services_comment = False
    
    # First, gather all existing includes
    existing_content = content[:include_end]
    
    # Add a blank line if there isn't one before # services
    if not existing_content[-1].strip() == '':
        new_includes.append('\n')
    
    # Add services comment if it doesn't exist
    if not any('# individual services' in line for line in content):
        new_includes.append('  # individual services\n')
    
    # Add service includes that don't already exist
    for service in sorted(services):
        include_line = f'  - path: ./{service}/docker-compose.yml.j2\n'
        if f'  - path: ./{service}/docker-compose.yml.j2' not in existing_includes:
            new_includes.append(include_line)
    
    # Combine everything
    updated_content = (
        content[:include_end] +
        new_includes +
        content[include_end:]
    )
    
    # Write the updated content
    with open(file_path, 'w') as f:
        f.writelines(updated_content)

def split_services(file_path):
    """Split docker-compose services into individual files."""
    try:
        # Read the original file
        with open(file_path, 'r') as f:
            content = f.read()
        
        # Get the base directory
        base_dir = Path(file_path).parent
        
        # Find service names
        services = []
        in_services = False
        for line in content.split('\n'):
            if line.strip() == 'services:':
                in_services = True
                continue
            
            if in_services and line.startswith('  ') and ':' in line and not line.startswith('    '):
                service_name = line.strip().split(':')[0]
                services.append(service_name)
        
        # Process each service
        for service_name in services:
            # Create service directory
            service_dir = base_dir / service_name
            service_dir.mkdir(exist_ok=True)
            
            # Extract service block and remove anchors
            service_block = extract_service_block(content, service_name)
            
            # Write the new compose file
            compose_path = service_dir / 'docker-compose.yml.j2'
            with open(compose_path, 'w') as f:
                f.write(service_block)
            
            print(f"Created {compose_path}")
        
        # Update the main compose file
        update_main_compose(file_path, services)
        print("Updated main docker-compose.yml.j2 with new includes")
            
    except Exception as e:
        print(f"Error: {e}")
        raise

def main():
    compose_file = "/home/josh/Code/ansible/nas-infra/docker/neo/docker-compose.yml.j2"
    
    try:
        split_services(compose_file)
        print("Successfully split all services and updated includes.")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    main()