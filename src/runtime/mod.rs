use sel4_sys::{seL4_CPtr, seL4_Word};
use std::collections::HashMap;
use sel4_sys::{seL4_CPtr, seL4_Word, seL4_Result};
use crate::parser::ast::{Definition, Invocation};

pub struct HardwareMapping {
    gpio_cap: seL4_CPtr,
    ncl_state: NCLState,
}

#[derive(Debug, Clone)]
pub enum NCLState {
    Null,
    Data(seL4_Word),
    Transitioning,
}

pub struct Runtime {
    // Capability space
    cspace_root: seL4_CPtr,
    // Hardware capabilities
    gpio_caps: HashMap<String, seL4_CPtr>,
    // Active definitions
    definitions: HashMap<String, crate::parser::ast::Definition>,
}



impl Runtime {
   pub fn new(cspace_root: seL4_CPtr) -> Self {
       Runtime {
           cspace_root,
           gpio_caps: HashMap::new(),
           definitions: HashMap::new(),
       }
   }

   // Request GPIO capability from seL4
   pub fn request_gpio(&mut self, name: &str) -> seL4_Result<seL4_CPtr> {
       // Request GPIO capability from seL4
       let gpio_cap = unsafe {
           // TODO: Replace with actual seL4 GPIO capability request
           0 as seL4_CPtr 
       };
       
       self.gpio_caps.insert(name.to_string(), gpio_cap);
       Ok(gpio_cap)
   }

   // Install a new definition
   pub fn install_definition(&mut self, def: Definition) -> seL4_Result<()> {
       // Request capabilities for all inputs
       for input in &def.inputs {
           self.request_gpio(input)?;
       }

       // Store definition
       self.definitions.insert(def.name.clone(), def);
       Ok(())
   }

   // Execute an invocation
   pub fn execute(&mut self, inv: Invocation) -> seL4_Result<()> {
       let def = self.definitions.get(&inv.function)
           .ok_or(/* Definition not found error */)?;

       // Map arguments to hardware
       let mut input_states = HashMap::new();
       for (arg, input) in inv.arguments.iter().zip(&def.inputs) {
           let state = match arg.as_str() {
               "0" => NCLState::Data(0),
               "1" => NCLState::Data(1),
               _ => NCLState::Null,
           };
           input_states.insert(input.clone(), state);
       }

       // Create hardware mapping
       let mapping = HardwareMapping::new(
           self.gpio_caps.get(&def.inputs[0]).unwrap().clone(),
           NCLState::Null,
       );

       // Start execution
       self.execute_mapping(mapping, &def.resolution)?;

       Ok(())
   }

   fn execute_mapping(&self, mapping: HardwareMapping, resolution: &ResolutionTable) -> seL4_Result<()> {
       // TODO: Implement NULL Convention Logic timing
       // TODO: Handle GPIO operations through seL4

       Ok(())
   }
}

impl HardwareMapping {
   pub fn new(gpio_cap: seL4_CPtr, initial_state: NCLState) -> Self {
       HardwareMapping {
           gpio_cap,
           ncl_state: initial_state,
       }
   }

   pub fn set_state(&mut self, new_state: NCLState) -> seL4_Result<()> {
       match (&self.ncl_state, &new_state) {
           (NCLState::Data(_), NCLState::Data(_)) => {
               // Must transition through NULL
               self.ncl_state = NCLState::Null;
               // Wait for NULL propagation
               // TODO: Implement proper timing
               self.ncl_state = new_state;
           }
           (NCLState::Null, NCLState::Data(_)) => {
               self.ncl_state = new_state;
           }
           _ => {}
       }
       Ok(())
   }
}