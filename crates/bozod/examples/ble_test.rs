//! Minimal BLE test to debug CoreBluetooth initialization on macOS.

use btleplug::api::Manager as _;
use btleplug::platform::Manager;

#[tokio::main]
async fn main() {
    println!("creating manager...");
    match Manager::new().await {
        Ok(manager) => {
            println!("manager created!");
            match manager.adapters().await {
                Ok(adapters) => println!("found {} adapter(s)", adapters.len()),
                Err(e) => eprintln!("adapters error: {}", e),
            }
        }
        Err(e) => eprintln!("manager error: {}", e),
    }
}
