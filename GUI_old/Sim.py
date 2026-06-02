"""
光通信链路联合仿真框架
读取JSON拓扑文件，按连接顺序调用各组件的MATLAB函数进行仿真。
可复用：支持任意符合格式的JSON文件，只需注册组件类型对应的处理函数。
"""

import json
from collections import deque
from typing import Dict, List, Any, Callable, Optional
import numpy as np

# 尝试导入MATLAB引擎（可选，若未安装则使用模拟模式）
try:
    import matlab.engine
    MATLAB_AVAILABLE = True
except ImportError:
    MATLAB_AVAILABLE = False
    print("Warning: MATLAB Engine for Python not installed. Using mock mode.")


class SimulationEngine:
    """仿真引擎：解析拓扑、排序、调度组件执行"""

    def __init__(self):
        self.components = []          # 原始组件列表
        self.connections = []         # 原始连接列表
        self.nodes = {}               # {组件seq_id: 组件信息}
        self.edges = []               # (src_id, tgt_id, src_port, tgt_port)
        self.adj = {}                 # 邻接表 {src_id: [tgt_id]}
        self.indegree = {}            # 入度 {node_id: count}
        self.execution_order = []     # 拓扑排序后的节点ID列表
        self.output_cache = {}        # {node_id: {output_port: data}}
        self.handlers = {}            # {component_type: callable}
        self.eng = None               # MATLAB引擎实例

    def load(self, json_path: str):
        """加载JSON拓扑文件"""
        with open(json_path, 'r', encoding='utf-8') as f:
            data = json.load(f)

        self.components = data.get("components", [])
        self.connections = data.get("connections", [])

        # 建立节点字典，按seq_id索引
        self.nodes = {}
        for comp in self.components:
            sid = comp["seq_id"]
            self.nodes[sid] = comp

        # 解析连接关系，构建边列表和邻接表
        self.edges = []
        self.adj = {sid: [] for sid in self.nodes}
        self.indegree = {sid: 0 for sid in self.nodes}

        for conn in self.connections:
            src = conn["source_id"]
            tgt = conn["target_id"]
            src_port = conn.get("source_port", "out")
            tgt_port = conn.get("target_port", "in")
            self.edges.append((src, tgt, src_port, tgt_port))
            self.adj[src].append(tgt)
            self.indegree[tgt] += 1

    def register_handler(self, component_type: str, handler: Callable):
        """
        注册组件类型的处理函数
        handler签名: handler(inputs: Dict[str, Any], eng=None) -> Dict[str, Any]
        - inputs: 输入端口名 -> 数据
        - eng: MATLAB引擎实例（可选）
        - 返回: 输出端口名 -> 数据
        """
        self.handlers[component_type] = handler

    def _topological_sort(self) -> List[int]:
        """Kahn算法拓扑排序，返回节点ID列表"""
        indegree = self.indegree.copy()
        q = deque([node for node, deg in indegree.items() if deg == 0])
        order = []
        while q:
            node = q.popleft()
            order.append(node)
            for neighbor in self.adj[node]:
                indegree[neighbor] -= 1
                if indegree[neighbor] == 0:
                    q.append(neighbor)
        if len(order) != len(self.nodes):
            raise ValueError("Graph contains a cycle! Cannot execute.")
        return order

    def _gather_inputs(self, node_id: int) -> Dict[str, Any]:
        """收集指向该节点的所有输入数据（按输入端口名组织）"""
        inputs = {}
        for src, tgt, src_port, tgt_port in self.edges:
            if tgt == node_id:
                # 源节点的输出缓存中提取对应端口的数据
                src_output = self.output_cache.get(src, {})
                if src_port not in src_output:
                    raise KeyError(f"Node {src} has no output port '{src_port}'")
                inputs[tgt_port] = src_output[src_port]
        return inputs

    def run(self, start_matlab: bool = True) -> Dict[str, Any]:
        """
        执行仿真
        start_matlab: 是否启动MATLAB引擎（若已存在可复用）
        返回最后一个节点的输出字典
        """
        # 启动MATLAB引擎（如果需要）
        if start_matlab and MATLAB_AVAILABLE and self.eng is None:
            self.eng = matlab.engine.start_matlab()
            print("MATLAB engine started.")

        # 拓扑排序
        self.execution_order = self._topological_sort()
        print(f"Execution order (seq_id): {self.execution_order}")

        # 按序执行组件
        for node_id in self.execution_order:
            comp = self.nodes[node_id]
            comp_type = comp["type"]
            comp_name = comp.get("name", comp_type)

            if comp_type not in self.handlers:
                raise ValueError(f"No handler registered for component type '{comp_type}'")

            # 收集输入
            inputs = self._gather_inputs(node_id)
            print(f"Executing {comp_name} (type={comp_type}) with inputs: {list(inputs.keys())}")

            # 调用处理函数
            handler = self.handlers[comp_type]
            outputs = handler(inputs, eng=self.eng)

            # 缓存输出
            self.output_cache[node_id] = outputs
            print(f"  -> Output ports: {list(outputs.keys())}")

        # 返回最后一个节点的输出（通常为DownRxDSP）
        if self.execution_order:
            last_id = self.execution_order[-1]
            return self.output_cache.get(last_id, {})
        else:
            return {}

    def close(self):
        """关闭MATLAB引擎"""
        if self.eng is not None:
            self.eng.quit()
            self.eng = None


# ----------------------------------------------------------------------
# 示例：为用户的实际MATLAB函数编写适配器
# 假设所有MATLAB函数都放在 ./matlab_functions/ 目录下，函数名与组件类型相同。
# 每个MATLAB函数的接口约定：
#   output = func(input1, input2, ...)   % 单输出
#   或者 [out1, out2] = func(...)         % 多输出
# 本框架要求每个组件的处理函数返回字典 {端口名: 数据}。
# 下面提供通用的MATLAB调用包装器（处理单输出情况，多输出需根据具体函数定制）。
# ----------------------------------------------------------------------

def matlab_single_output_wrapper(matlab_func_name: str, output_port_name: str = "out"):
    """
    生成一个包装函数，用于调用返回单个输出的MATLAB函数。
    该包装函数假定：
      - 输入字典中的值按端口名顺序传入MATLAB函数（顺序由调用时决定，建议固定顺序）。
      - 更健壮的做法是根据端口名映射到函数参数，这里简化为取字典的所有值组成的列表。
    """
    def wrapper(inputs: Dict[str, Any], eng=None) -> Dict[str, Any]:
        if eng is None:
            raise RuntimeError("MATLAB engine not available")
        # 将输入字典的值转换为列表（按端口名排序保证稳定顺序，实际应依据函数参数顺序）
        # 这里简单按字母顺序排序，用户可根据需要调整
        ordered_inputs = [inputs[k] for k in sorted(inputs.keys())]
        # 转换为MATLAB类型（如果是numpy数组，需要转换为matlab.double）
        ml_inputs = []
        for arg in ordered_inputs:
            if isinstance(arg, np.ndarray):
                ml_inputs.append(matlab.double(arg.tolist()))
            else:
                ml_inputs.append(arg)
        # 调用MATLAB函数
        result = getattr(eng, matlab_func_name)(*ml_inputs)
        # 将MATLAB结果转换回Python类型（根据需要）
        if isinstance(result, matlab.double):
            result = np.array(result)
        return {output_port_name: result}
    return wrapper


def matlab_multi_output_wrapper(matlab_func_name: str, output_port_names: List[str]):
    """
    用于返回多个输出的MATLAB函数。
    示例：outputs = func(...) 在MATLAB中返回多个参数，Python引擎会返回一个tuple。
    """
    def wrapper(inputs: Dict[str, Any], eng=None) -> Dict[str, Any]:
        if eng is None:
            raise RuntimeError("MATLAB engine not available")
        # 按固定顺序组织输入（同样按键名排序）
        ordered_inputs = [inputs[k] for k in sorted(inputs.keys())]
        ml_inputs = []
        for arg in ordered_inputs:
            if isinstance(arg, np.ndarray):
                ml_inputs.append(matlab.double(arg.tolist()))
            else:
                ml_inputs.append(arg)
        results = getattr(eng, matlab_func_name)(*ml_inputs, nargout=len(output_port_names))
        # 确保results是元组
        if not isinstance(results, tuple):
            results = (results,)
        output_dict = {}
        for name, val in zip(output_port_names, results):
            if isinstance(val, matlab.double):
                val = np.array(val)
            output_dict[name] = val
        return output_dict
    return wrapper


# ----------------------------------------------------------------------
# 模拟模式（无MATLAB时使用）：打印日志并传递虚拟数据
# ----------------------------------------------------------------------
def mock_handler(inputs: Dict[str, Any], eng=None) -> Dict[str, Any]:
    """模拟处理函数：返回输入数据的简单变换"""
    print(f"  Mock: inputs = {inputs}")
    # 简单模拟：如果有输入，取第一个输入值并乘以1.0返回；否则返回默认值
    if inputs:
        # 取任意一个输入数据
        sample = next(iter(inputs.values()))
        # 如果是numpy数组，复制；否则返回原值
        if isinstance(sample, np.ndarray):
            output = sample.copy()
        else:
            output = sample
    else:
        output = 1.0
    return {"out": output}


# ----------------------------------------------------------------------
# 使用示例
# ----------------------------------------------------------------------
if __name__ == "__main__":
    # 创建引擎实例
    engine = SimulationEngine()

    # 加载JSON文件（假设down.json在当前目录）
    engine.load("down.json")

    # 注册组件处理函数
    # 方式一：使用实际的MATLAB函数包装器（需确保MATLAB引擎可用且函数在路径中）
    if MATLAB_AVAILABLE:
        # 为每个组件类型注册MATLAB调用包装器（这里假设所有组件都是单输出，输出端口名为"out"）
        component_types = ["DownTxDSP", "DAC", "Driver", "LaserCW", "Modulator",
                           "OA", "VOA", "ICR", "TIA", "ADC", "DownRxDSP", "Fiber"]
        for ctype in component_types:
            engine.register_handler(ctype, matlab_single_output_wrapper(ctype, "out"))
    else:
        # 方式二：注册模拟处理函数（仅供测试框架逻辑）
        component_types = ["DownTxDSP", "DAC", "Driver", "LaserCW", "Modulator",
                           "OA", "VOA", "ICR", "TIA", "ADC", "DownRxDSP", "Fiber"]
        for ctype in component_types:
            engine.register_handler(ctype, mock_handler)

    # 运行仿真
    final_output = engine.run(start_matlab=MATLAB_AVAILABLE)

    print("\n=== Simulation Complete ===")
    print("Final output (last component):", final_output)

    # 关闭MATLAB引擎
    engine.close()