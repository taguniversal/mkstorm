use crate::sel4::{Result};
use crate::parser::ast::{Definition};
use crate::sel4::fpga_config::{FpgaConfig, FpgaRegion, FpgaRegionMapping};


 // Supporting types
 struct NclRegister {
    data_rail: u32,  // FPGA register location
    null_rail: u32,  // NCL requires dual-rail logic
    name: String,
}

struct NclCompletion {
    data_detect: u32,   // Register for data rail completion
    null_detect: u32,   // Register for null rail completion
    output_valid: u32,  // Final completion signal
 }

struct LookupTable {
    input_pattern: String,
    output_value: String,
    config: u32,     // FPGA LUT configuration
}

pub struct FpgaCircuit {
    definition: Definition,
    region: FpgaRegionMapping,
}

impl FpgaCircuit {
    pub fn new(definition: Definition, config: &mut FpgaConfig) -> Result<Self> {
        // Allocate FPGA region for this circuit
        let region = FpgaRegionMapping::new(config, FpgaRegion::Configuration, 1024)?;
        
        // Convert resolution table to hardware
        let mut circuit = Self { definition, region };
        circuit.synthesize()?;
        
        Ok(circuit)
    }

    fn allocate_register(&mut self) -> Result<u32> {
        // For now, use a simple incrementing counter for resource allocation
        static mut NEXT_REG: u32 = 0;
        unsafe {
            let reg = NEXT_REG;
            NEXT_REG += 1;
            
            // Configure the FPGA register through memory mapping
            self.region.write_word(
                (reg * 4) as usize,  // Simple addressing scheme
                0  // Initial value
            )?;
            
            Ok(reg)
        }
    }
 
    fn allocate_lut(&self) -> Result<u32> {
        static mut NEXT_LUT: u32 = 1000;  // Start LUTs at different address range
        unsafe {
            let lut = NEXT_LUT;
            NEXT_LUT += 1;
            Ok(lut)
        }
    }
 
    fn create_completion_detection(&mut self) -> Result<NclCompletion> {
        // Create completion detection circuit
        let completion = NclCompletion {
            data_detect: self.allocate_register()?,
            null_detect: self.allocate_register()?,
            output_valid: self.allocate_register()?,
        };
 
        // Configure completion detection logic
        self.configure_completion(&completion)?;
 
        Ok(completion)
    }
 
    fn configure_completion(&mut self, completion: &NclCompletion) -> Result<()> {
        // Write completion detection configuration
        // This creates an OR tree of all data/null rails
        let config_word = 0xFFFF_FFFF;  // Full OR configuration
        self.region.write_word(
            completion.data_detect as usize * 4,
            config_word
        )?;
        
        self.region.write_word(
            completion.null_detect as usize * 4,
            config_word
        )?;
 
        Ok(())
    }
 
    fn configure_routing(
        &mut self,
        inputs: &[NclRegister],
        luts: &[LookupTable],
        completion: &NclCompletion
    ) -> Result<()> {
        // Configure input routing to LUTs
        for (i, input) in inputs.iter().enumerate() {
            // Route each input to corresponding LUT bits
            for lut in luts {
                let bit_value = match lut.input_pattern.chars().nth(i) {
                    Some('1') => 1,
                    Some('0') => 0,
                    _ => continue,
                };
                
                // Configure routing in FPGA fabric
                self.configure_route(
                    input.data_rail,
                    lut.config,
                    i,
                    bit_value
                )?;
            }
        }
 
        // Route LUT outputs to completion detection
        for (i, lut) in luts.iter().enumerate() {
            self.configure_route(
                lut.config,
                completion.data_detect,
                i,
                1  // Connect to completion detection
            )?;
        }
 
        Ok(())
    }
 
    fn configure_route(
        &mut self,
        from: u32,
        to: u32,
        bit_position: usize,
        value: u32
    ) -> Result<()> {
        // Convert the route configuration to usize
        let route_config = ((from as usize) << 16) | 
                          ((to as usize) << 8) | 
                          bit_position;
        
        self.region.write_word(
            0x10000 + (4 * from as usize),  // Routing configuration area
            route_config | ((value as usize) << 31)  // Include desired value
        )?;
        
        Ok(())
    }

    fn synthesize(&mut self) -> Result<()> {
        // First, create NULL Convention Logic registers for inputs
        let ncl_inputs = self.create_ncl_inputs()?;
        
        // Create lookup tables from resolution patterns
        let luts = self.create_luts()?;
                
        // Create NCL completion detection
        let completion = self.create_completion_detection()?;
                
        // Configure routing between components
        self.configure_routing(&ncl_inputs, &luts, &completion)?;
                
        Ok(())
    }

    fn create_ncl_inputs(&self) -> Result<Vec<NclRegister>> {
        let mut registers = Vec::new();
        for input in &self.definition.inputs {
            // Each NCL input needs data and null detection
            let reg = NclRegister {
                data_rail: self.allocate_register()?,
                null_rail: self.allocate_register()?,
                name: input.clone(),
            };
            registers.push(reg);
        }
        Ok(registers)
    }

    fn create_luts(&self) -> Result<Vec<LookupTable>> {
        let mut luts = Vec::new();
        for pattern in &self.definition.resolution.patterns {
            let lut = LookupTable {
                input_pattern: pattern.0.clone(),
                output_value: pattern.1.clone(),
                config: self.allocate_lut()?,
            };
            luts.push(lut);
        }
        Ok(luts)
    }

    }
 

   

