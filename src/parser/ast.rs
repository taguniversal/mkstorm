#[derive(Debug, Clone, PartialEq)]
pub struct Definition {
    pub name: String,
    pub inputs: Vec<String>,
    pub outputs: Vec<String>,
    pub resolution: ResolutionTable,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ResolutionTable {
    pub patterns: Vec<(String, String)>  // (input_pattern, output_value)
}

#[derive(Debug, Clone, PartialEq)]
pub struct Invocation {
    pub dest: String,
    pub function: String,
    pub arguments: Vec<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum InvocationNode {
    Definition(Definition),
    Invocation(Invocation),
}