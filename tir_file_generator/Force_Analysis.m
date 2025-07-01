function [] = Force_Analysis
msg = "";
opts = ["Not normalized values" "Normalized values" ];
file = menu(msg,opts);
switch file
    case 1
msg = "";
opts = ["Compound Analysis" "Compound Comparison"];
choice = menu(msg,opts);
switch choice
    case 1
        Compound_Analysis_STC7;
        
    case 2
        Compound_Comparison_STC7;
        
end
    case 2
        global C
        prompt = "insert the value of Cornering Stiffness ";
        C = input(prompt);
        msg = "";
opts = ["Compound Analysis" "Compound Comparison"];
choice = menu(msg,opts);
switch choice
    case 1
        Compound_AnalysisN;
        
    case 2
        Compound_Comparison_N;
end
end