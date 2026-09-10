with open('relay12/tests/test_ci_gates.py', 'r') as f:
    text = f.read()

bad = """        self.assertEqual(padding, {
            "D3D10DDIARG_CREATEDEVICE": [(76, 4)],
            "D3DDDICB_ESCAPE": [(12, 4), (28, 4)],
            "D3DDDICB_SYNCTOKEN": [(12, 4)],
        })"""

good = """        self.assertEqual(padding, {
            "D3D10DDIARG_CREATEDEVICE": [(76, 4)],
            "D3D11DDIARG_CREATEDEFERREDCONTEXT": [(36, 4)],
            "D3D11DDI_HANDLESIZE": [(4, 4)],
            "D3DDDICB_ESCAPE": [(12, 4), (28, 4)],
            "D3DDDICB_SYNCTOKEN": [(12, 4)],
        })"""

text = text.replace(bad, good)
with open('relay12/tests/test_ci_gates.py', 'w') as f:
    f.write(text)
