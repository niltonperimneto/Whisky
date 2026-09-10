with open('relay12/tests/test_ci_gates.py', 'r') as f:
    text = f.read()

if 'import os' not in text:
    text = 'import os\n' + text

dict_bad = """'D3D10DDIARG_CREATEDEVICE': [(76, 4)],
            'D3DDDICB_ESCAPE': [(12, 4), (28, 4)],
            'D3DDDICB_SYNCTOKEN': [(12, 4)],"""

dict_good = """'D3D10DDIARG_CREATEDEVICE': [(76, 4)],
            'D3D11DDIARG_CREATEDEFERREDCONTEXT': [(36, 4)],
            'D3D11DDI_HANDLESIZE': [(4, 4)],
            'D3DDDICB_ESCAPE': [(12, 4), (28, 4)],
            'D3DDDICB_SYNCTOKEN': [(12, 4)],"""

if "'D3D11DDIARG_CREATEDEFERREDCONTEXT'" not in text:
    text = text.replace(dict_bad, dict_good)

with open('relay12/tests/test_ci_gates.py', 'w') as f:
    f.write(text)

