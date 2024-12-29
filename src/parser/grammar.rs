use nom::{
    IResult,
    branch::alt,
    bytes::complete::{take_while1, take_while},
    character::complete::{char, multispace0, multispace1, line_ending},
    combinator::{map, recognize},
    multi::{separated_list0, many0},
    sequence::{delimited, tuple}
};

use super::ast::{Definition, Invocation, InvocationNode, ResolutionTable};

// Basic identifier parser
fn identifier(input: &str) -> IResult<&str, String> {
    map(
        recognize(
            take_while1(|c: char| c.is_alphanumeric() || c == '_')
        ),
        String::from
    )(input)
}

// Parse destination like $A
fn destination(input: &str) -> IResult<&str, String> {
    map(
        tuple((
            char('$'),
            identifier
        )),
        |(_, name)| name
    )(input)
}

// Parse source like IN<>
fn source(input: &str) -> IResult<&str, String> {
    map(
        tuple((
            identifier,
            char('<'),
            char('>')
        )),
        |(name, _, _)| name
    )(input)
}

// Parse resolution pattern like "00:0"
fn resolution_pattern(input: &str) -> IResult<&str, (String, String)> {
    println!("Attempting to parse resolution pattern: {:?}", input);
    let (input, pattern) = take_while1(|c: char| c == '0' || c == '1')(input)?;
    println!("Found pattern: {}", pattern);
    
    let (input, _) = char(':')(input)?;
    let (input, value) = take_while1(|c: char| c == '0' || c == '1')(input)?;
    println!("Found value: {}", value);
    
    Ok((input, (pattern.to_string(), value.to_string())))
}

// Parse resolution inputs ($A$B)
fn resolution_inputs(input: &str) -> IResult<&str, Vec<String>> {
    println!("Attempting to parse resolution inputs: {:?}", input);
    let mut result = Vec::new();
    let (input, first) = destination(input)?;
    result.push(first);
    
    let (current_input, next) = destination(input)?;
    result.push(next);
    
    Ok((current_input, result))
}

fn comment(input: &str) -> IResult<&str, ()> {
    println!("Attempting to parse comment: {:?}", input);
    let (input, _) = char('#')(input)?;
    let (input, _) = take_while(|c| c != '\n')(input)?;
    let (input, _) = line_ending(input)?;
    Ok((input, ()))
}

fn ws(input: &str) -> IResult<&str, ()> {
    println!("Processing whitespace: {:?}", input);
    many0(
        alt((
            // Try multispace first
            map(multispace1, |_| ()),
            // Then try line endings
            map(line_ending, |_| ()),
            // Finally try comments
            comment
        ))
    )(input)
    .map(|(next_input, _)| (next_input, ()))
}

// Parse full definition
fn definition(input: &str) -> IResult<&str, InvocationNode> {
    println!("Attempting to parse definition: {:?}", input);
    let (input, name) = identifier(input)?;
    println!("Found identifier: {}", name);
    
    let (input, _) = char('[')(input)?;
    println!("Found opening bracket");
    
    let (input, _) = char('(')(input)?;
    let (input, inputs) = separated_list0(char(','), destination)(input)?;
    let (input, _) = char(')')(input)?;
    println!("Parsed inputs: {:?}", inputs);
    
    let (input, _) = char('(')(input)?;
    let (input, outputs) = separated_list0(char(','), source)(input)?;
    let (input, _) = char(')')(input)?;
    println!("Parsed outputs: {:?}", outputs);
    
    let (input, _) = multispace1(input)?;
    let (input, _) = char('[')(input)?;
    println!("Starting resolution table");
    
    // Parse resolution inputs ($A$B)
    let (input, _res_inputs) = resolution_inputs(input)?;
    println!("Parsed resolution inputs: {:?}", _res_inputs);
    
    let (input, _) = char(']')(input)?;
    let (input, _) = multispace1(input)?;
    
    let (input, resolutions) = separated_list0(
        multispace1,
        resolution_pattern
    )(input)?;
    println!("Parsed resolutions: {:?}", resolutions);
    
    let (input, _) = char(']')(input)?;
    
    Ok((input, InvocationNode::Definition(Definition {
        name,
        inputs,
        outputs,
        resolution: ResolutionTable { patterns: resolutions },
    })))
}

// Parse arguments for invocations
fn argument(input: &str) -> IResult<&str, String> {
    alt((
        map(char('0'), |c| c.to_string()),
        map(char('1'), |c| c.to_string()),
        identifier
    ))(input)
}

// Parse invocation like R<OR(0,1)>
fn invocation(input: &str) -> IResult<&str, InvocationNode> {
    println!("Attempting to parse invocation: {:?}", input);
    map(
        tuple((
            identifier,
            char('<'),
            identifier,
            char('('),
            separated_list0(
                char(','),
                delimited(multispace0, argument, multispace0)
            ),
            char(')'),
            char('>')
        )),
        |(dest, _, function, _, arguments, _, _)| {
            InvocationNode::Invocation(Invocation {
                dest,
                function,
                arguments,
            })
        }
    )(input)
}

// Top level parser
fn program(input: &str) -> IResult<&str, Vec<InvocationNode>> {
    println!("Attempting to parse program: {:?}", input);
    let (input, _) = ws(input)?;
    println!("After initial whitespace: {:?}", input);
    
    let mut result = Vec::new();
    let mut current_input = input;
    
    while !current_input.is_empty() {
        match alt((definition, invocation))(current_input) {
            Ok((remaining, node)) => {
                println!("Successfully parsed node");
                result.push(node);
                let (after_ws, _) = ws(remaining)?;
                current_input = after_ws;
            },
            Err(nom::Err::Error(e)) => {
                println!("Failed to parse node: {:?}", e);
                break;
            },
            Err(e) => return Err(e),
        }
    }
    
    Ok((current_input, result))
}

#[derive(Debug, thiserror::Error)]
pub enum ParseError {
    #[error("Parse error: {0}")]
    Nom(String),
    #[error("Invalid input: {0}")]
    InvalidInput(String),
}

pub fn parse(input: &str) -> Result<Vec<InvocationNode>, ParseError> {
    println!("Input: {:?}", input);
    match program(input) {
        Ok(("", result)) => {
            println!("Successfully parsed!");
            Ok(result)
        },
        Ok((remaining, _)) => {
            println!("Remaining: {:?}", remaining);
            Err(ParseError::InvalidInput(
                format!("Unparsed input remaining: {}", remaining)
            ))
        },
        Err(e) => {
            println!("Error: {:?}", e);
            Err(ParseError::Nom(e.to_string()))
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_basic_definition() {
        let input = "OR[($A,$B)(IN<>) [$A$B] 00:0 01:1 10:1 11:1]";
        let result = parse(input).unwrap();
        assert_eq!(result.len(), 1);
        match &result[0] {
            InvocationNode::Definition(def) => {
                assert_eq!(def.name, "OR");
                assert_eq!(def.inputs, vec!["A", "B"]);
                assert_eq!(def.outputs, vec!["IN"]);
                assert_eq!(def.resolution.patterns.len(), 4);
            }
            _ => panic!("Expected Definition"),
        }
    }

    #[test]
    fn test_basic_invocation() {
        let input = "R<OR(0,1)>";
        let result = parse(input).unwrap();
        assert_eq!(result.len(), 1);
        match &result[0] {
            InvocationNode::Invocation(inv) => {
                assert_eq!(inv.dest, "R");
                assert_eq!(inv.function, "OR");
                assert_eq!(inv.arguments, vec!["0", "1"]);
            }
            _ => panic!("Expected Invocation"),
        }
    }
}