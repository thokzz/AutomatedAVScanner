AutomatedAVScanner

https://raw.githubusercontent.com/thokzz/AutomatedAVScanner/refs/heads/main/assets/AutomatedAVScanner%20App%20Scanning.png

Automated USB & External Drive Virus Scanner for macOS
DriveScanner is a powerful macOS utility designed to automatically scan external drives for malware the moment they're connected. Built with Swift 6 and a modern SwiftUI interface, this application provides enterprise-grade protection with minimal user interaction required.

🔍 Key Features

Automatic Scanning: Scans connected drives instantly without manual intervention
Multi-Partition Detection: Intelligently handles drives with multiple partitions
Safe Drive Ejection: Secure ejection only after all partitions are scanned and report printed
Receipt Printing: Automatically prints scan report upon completion
Scan History: Maintains detailed history of all scans performed
Smart File Filtering: Optimizes scan speed by selectively filtering safe file types
ClamAV Integration: Uses industry-standard ClamAV engine for reliable virus detection
Customizable Themes: Multiple visual themes to match your preference

📋 Technical Architecture
DriveScanner leverages a multi-component architecture to deliver reliable and responsive performance:

SwiftUI Interface Layer: Modern reactive interface that updates in real-time
Volume Monitor: Continuously monitors system for new drive connections
Physical Drive Tracker: Associates related partitions for cohesive scanning
ClamAV Integration: Embedded virus scanning engine with regularly updated definitions
Transaction Manager: Maintains persistent history of all scan operations
Audio Feedback System: Provides audio cues for critical operations

💻 Development Approach
This application was created with a combination of:

Swift 6 for core application logic
SwiftUI for the modern, responsive interface
AI Assistance from ChatGPT 4.0 and Claude 3.7 Sonnet for development
ClamAV integration for virus detection
Cocoa APIs for system integration

The development process leveraged modern AI tools to accelerate coding while maintaining high code quality and performance.
🔧 System Requirements

macOS 12.4 (Monterey) or later
Internet connection for virus definition updates
Connected printer for scan reports (optional)

🚀 Getting Started

Download the latest release from the releases page
Install DriveScanner by dragging to your Applications folder
Launch the application and grant the requested permissions
Connect an external drive to begin automatic scanning

🖨️ Printing Setup
For best results with receipt printing:

Any thermal receipt printer compatible with macOS
Standard desktop printers also supported with adjusted formatting

🛡️ Security Notes
DriveScanner requires several permissions to function properly:

Full Disk Access: To scan external drives comprehensively
Accessibility: For automated drive ejection
Print Access: For automatic report printing

These permissions are necessary for the application to function as intended and are used solely for the purpose of drive scanning and reporting.
📝 Development Notes
This project demonstrates several advanced Swift and macOS development concepts:

Integration with system events for drive mounting/unmounting
Working with printer and audio subsystems
Concurrent operations with modern Swift concurrency
SwiftUI state management across a complex application
External process management for virus scanning

✨ Future Development
Planned features for upcoming releases:

Network share scanning capability
Cloud scanning result backup
Enhanced scan statistics and reporting
Enterprise deployment configurations

📜 License
This project is licensed under the MIT License - see the LICENSE file for details.
👨‍💻 About the Developer

I created this project as a portfolio piece to demonstrate advanced Swift development capabilities while leveraging modern AI tools like ChatGPT 4.0 and Claude 3.7 Sonnet to enhance the development process.
