pub mod fpga;
pub mod fpga_config;

pub use fpga::*;
pub use fpga_config::*;

// Basic seL4 types
pub type CPtr = usize;
pub type Word = usize;

pub struct CapRights {
   pub read: bool,
   pub write: bool,
   pub grant: bool,
}

pub struct GpioConfig {
    pub pin: Word,
    pub direction: GpioDirection,
}

pub trait GpioOps {
    fn configure(&self, config: GpioConfig) -> Result<()>;
    fn write(&self, value: bool) -> Result<()>;
    fn read(&self) -> Result<bool>;
}

#[derive(Debug)]
pub enum Error {
   InvalidCapability,
   PermissionDenied,
   ResourceExhausted,
}

pub type Result<T> = std::result::Result<T, Error>;