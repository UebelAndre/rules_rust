use wasm_bindgen::prelude::*;

#[wasm_bindgen]
pub fn double(i: i32) -> i32 {
    i * 2
}

#[allow(dead_code)]
fn main() {
    println!("Hello {}", double(2));
}

#[cfg(test)]
mod tests {
    use super::double;

    use wasm_bindgen_test::*;

    #[wasm_bindgen_test]
    fn test_double() {
        assert_eq!(double(2), 4);
        assert_eq!(double(3), 6);
        assert_eq!(double(4), 8);
    }
}
